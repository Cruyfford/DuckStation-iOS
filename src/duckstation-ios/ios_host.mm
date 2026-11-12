// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// Host implementation for the iOS frontend. Based on the structure of the headless
// regression-test host, with a real CPU thread, Metal window and persistent settings.

#include "ios_host.h"

#include "core/achievements.h"
#include "core/bios.h"
#include "core/controller.h"
#include "core/fullscreen_ui.h"
#include "core/game_list.h"
#include "core/gpu.h"
#include "core/host.h"
#include "core/settings.h"
#include "core/system.h"

#include "util/gpu_device.h"
#include "util/imgui_fullscreen.h"
#include "util/imgui_manager.h"
#include "util/ini_settings_interface.h"
#include "util/input_manager.h"
#include "util/platform_misc.h"

#include "common/error.h"
#include "common/file_system.h"
#include "common/log.h"
#include "common/path.h"
#include "common/string_util.h"

#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

Log_SetChannel(IOSHost);

extern "C" void SDL_SetMainReady(void);

namespace IOSHost {
static void CPUThreadMain();
static void ProcessCPUQueue();
static void PostEvent(Event event, std::string message = {});
static bool IsOnCPUThread();
} // namespace IOSHost

static std::unique_ptr<INISettingsInterface> s_settings;
static std::string s_documents_dir;
static std::string s_games_dir;

static std::thread s_cpu_thread;
static std::thread::id s_cpu_thread_id;
static std::mutex s_queue_mutex;
static std::condition_variable s_queue_cv;
static std::deque<std::function<void()>> s_queue;
static std::atomic_bool s_shutdown_requested{false};

static IOSHost::EventCallback s_event_callback = nullptr;

static std::mutex s_view_mutex;
static void* s_render_view = nullptr;
static int s_render_width = 0;
static int s_render_height = 0;
static float s_render_scale = 1.0f;

//////////////////////////////////////////////////////////////////////////
// Setup
//////////////////////////////////////////////////////////////////////////

static void SetDefaultIOSSettings(SettingsInterface& si)
{
  System::SetDefaultSettings(si);
  EmuFolders::Save(si);

  // Touch-friendly defaults.
  si.SetStringValue("Pad1", "Type", Controller::GetControllerInfo(ControllerType::AnalogController)->name);
  si.SetStringValue("Pad2", "Type", Controller::GetControllerInfo(ControllerType::None)->name);
  si.SetStringValue("CPU", "ExecutionMode", Settings::GetCPUExecutionModeName(CPUExecutionMode::CachedInterpreter));
  si.SetStringValue("Audio", "Backend", AudioStream::GetBackendName(AudioBackend::SDL));
  si.SetBoolValue("Main", "PauseOnFocusLoss", false);
  si.SetBoolValue("Main", "ConfirmPowerOff", false);
  si.SetBoolValue("Main", "EnableFullscreenUI", false);
  si.SetBoolValue("Logging", "LogToConsole", true);
  si.SetBoolValue("Logging", "LogToFile", false);
  si.SetBoolValue("InputSources", "SDL", true);
}

bool IOSHost::Initialize(const std::string& documents_dir, const std::string& bundle_dir, std::string* error)
{
  s_documents_dir = documents_dir;

  EmuFolders::AppRoot = bundle_dir;
  EmuFolders::DataRoot = documents_dir;
  // Not "resources": a top-level Resources folder makes CFBundle/installd treat the .app as an old-style bundle.
  EmuFolders::Resources = Path::Combine(bundle_dir, "dsdata");
  EmuFolders::SetDefaults();
  EmuFolders::Bios = Path::Combine(documents_dir, "BIOS");
  s_games_dir = Path::Combine(documents_dir, "Games");

  if (!FileSystem::DirectoryExists(EmuFolders::Resources.c_str()))
  {
    *error = "Resources folder is missing from the app bundle.";
    return false;
  }

  const std::string settings_path = Path::Combine(documents_dir, "settings.ini");
  const bool settings_exist = FileSystem::FileExists(settings_path.c_str());
  s_settings = std::make_unique<INISettingsInterface>(settings_path);
  Host::Internal::SetBaseSettingsLayer(s_settings.get());
  if (settings_exist)
    s_settings->Load();

  if (!settings_exist || s_settings->GetIntValue("Main", "SettingsVersion", 0) != 1)
  {
    SetDefaultIOSSettings(*s_settings);
    s_settings->SetIntValue("Main", "SettingsVersion", 1);
    s_settings->Save();
  }

  // Keep a log in Documents (visible in the Files app) so boot problems can be diagnosed on-device.
  s_settings->SetBoolValue("Logging", "LogToFile", true);
  Log::SetFileOutputParams(true, Path::Combine(documents_dir, "duckstation.log").c_str(), true);

  // Folders always live in Documents, even if the stored config points elsewhere.
  EmuFolders::LoadConfig(*s_settings);
  EmuFolders::Bios = Path::Combine(documents_dir, "BIOS");
  EmuFolders::EnsureFoldersExist();
  FileSystem::EnsureDirectoryExists(s_games_dir.c_str(), false);

  Error startup_error;
  if (!System::Internal::PerformEarlyHardwareChecks(&startup_error) ||
      !System::Internal::ProcessStartup(&startup_error))
  {
    *error = startup_error.GetDescription();
    return false;
  }

  // SDL must be told we don't use SDL_main before any subsystem is initialized.
  SDL_SetMainReady();

  s_shutdown_requested.store(false);
  s_cpu_thread = std::thread(&IOSHost::CPUThreadMain);
  return true;
}

void IOSHost::SetEventCallback(EventCallback callback)
{
  s_event_callback = callback;
}

std::string IOSHost::GetGamesDirectory()
{
  return s_games_dir;
}

std::string IOSHost::GetBIOSDirectory()
{
  return EmuFolders::Bios;
}

bool IOSHost::HasBIOS()
{
  return BIOS::HasAnyBIOSImages();
}

std::vector<std::string> IOSHost::ScanGames()
{
  static constexpr const char* extensions[] = {".cue", ".chd", ".pbp", ".m3u", ".iso", ".img", ".ecm", ".mds", ".exe",
                                               ".psexe", ".psf"};

  std::vector<std::string> ret;
  FileSystem::FindResultsArray results;
  FileSystem::FindFiles(s_games_dir.c_str(), "*",
                        FILESYSTEM_FIND_FILES | FILESYSTEM_FIND_RECURSIVE | FILESYSTEM_FIND_RELATIVE_PATHS, &results);
  for (const FILESYSTEM_FIND_DATA& fd : results)
  {
    for (const char* ext : extensions)
    {
      if (StringUtil::EndsWithNoCase(fd.FileName, ext))
      {
        ret.push_back(Path::Combine(s_games_dir, fd.FileName));
        break;
      }
    }
  }

  // A .bin with a matching .cue is listed via the cue; loose .bin files are still playable on their own.
  for (const FILESYSTEM_FIND_DATA& fd : results)
  {
    if (!StringUtil::EndsWithNoCase(fd.FileName, ".bin"))
      continue;

    const std::string full = Path::Combine(s_games_dir, fd.FileName);
    const std::string cue = Path::ReplaceExtension(full, "cue");
    if (!FileSystem::FileExists(cue.c_str()))
      ret.push_back(full);
  }

  std::sort(ret.begin(), ret.end(), [](const std::string& a, const std::string& b) {
    const std::string na(Path::GetFileName(a)), nb(Path::GetFileName(b));
    return StringUtil::Strcasecmp(na.c_str(), nb.c_str()) < 0;
  });
  return ret;
}

//////////////////////////////////////////////////////////////////////////
// CPU thread
//////////////////////////////////////////////////////////////////////////

bool IOSHost::IsOnCPUThread()
{
  return std::this_thread::get_id() == s_cpu_thread_id;
}

void IOSHost::ProcessCPUQueue()
{
  std::unique_lock lock(s_queue_mutex);
  while (!s_queue.empty())
  {
    std::function<void()> func = std::move(s_queue.front());
    s_queue.pop_front();
    lock.unlock();
    func();
    lock.lock();
  }
}

void IOSHost::CPUThreadMain()
{
  s_cpu_thread_id = std::this_thread::get_id();
  pthread_setname_np("DuckStation CPU");

  Error error;
  if (!System::Internal::CPUThreadInitialize(&error))
  {
    PostEvent(Event::Error, error.GetDescription());
    return;
  }

  while (!s_shutdown_requested.load(std::memory_order_acquire))
  {
    if (System::IsRunning())
    {
      System::Execute();
      continue;
    }

    {
      std::unique_lock lock(s_queue_mutex);
      s_queue_cv.wait_for(lock, std::chrono::milliseconds(16),
                          []() { return !s_queue.empty() || s_shutdown_requested.load(std::memory_order_acquire); });
    }

    ProcessCPUQueue();
    System::Internal::IdlePollUpdate();

    if (System::IsValid() && g_gpu_device)
      System::PresentDisplay(false, false);
  }

  if (System::IsValid())
    System::ShutdownSystem(false);

  System::Internal::CPUThreadShutdown();
}

void Host::PumpMessagesOnCPUThread()
{
  IOSHost::ProcessCPUQueue();
}

void Host::RunOnCPUThread(std::function<void()> function, bool block /* = false */)
{
  if (IOSHost::IsOnCPUThread())
  {
    function();
    return;
  }

  if (!block)
  {
    {
      std::unique_lock lock(s_queue_mutex);
      s_queue.push_back(std::move(function));
    }
    s_queue_cv.notify_one();
    return;
  }

  std::mutex done_mutex;
  std::condition_variable done_cv;
  bool done = false;
  {
    std::unique_lock lock(s_queue_mutex);
    s_queue.push_back([&function, &done_mutex, &done_cv, &done]() {
      function();
      std::unique_lock dlock(done_mutex);
      done = true;
      done_cv.notify_one();
    });
  }
  s_queue_cv.notify_one();

  std::unique_lock dlock(done_mutex);
  done_cv.wait(dlock, [&done]() { return done; });
}

void IOSHost::PostEvent(Event event, std::string message)
{
  EventCallback cb = s_event_callback;
  if (!cb)
    return;

  dispatch_async(dispatch_get_main_queue(), ^{
    cb(event, message.c_str());
  });
}

//////////////////////////////////////////////////////////////////////////
// Render window
//////////////////////////////////////////////////////////////////////////

void IOSHost::SetRenderView(void* view, int width_px, int height_px, float scale)
{
  std::unique_lock lock(s_view_mutex);
  s_render_view = view;
  s_render_width = width_px;
  s_render_height = height_px;
  s_render_scale = scale;
}

void IOSHost::ResizeRenderView(int width_px, int height_px, float scale)
{
  {
    std::unique_lock lock(s_view_mutex);
    s_render_width = width_px;
    s_render_height = height_px;
    s_render_scale = scale;
  }

  Host::RunOnCPUThread([width_px, height_px, scale]() {
    if (g_gpu_device)
    {
      g_gpu_device->ResizeWindow(width_px, height_px, scale);
      System::HostDisplayResized();
    }
  });
}

void IOSHost::ClearRenderView()
{
  std::unique_lock lock(s_view_mutex);
  s_render_view = nullptr;
}

std::optional<WindowInfo> Host::AcquireRenderWindow(bool recreate_window)
{
  std::unique_lock lock(s_view_mutex);
  if (!s_render_view)
  {
    ERROR_LOG("No render view set");
    return std::nullopt;
  }

  WindowInfo wi;
  wi.type = WindowInfo::Type::MacOS; // Metal device treats window_handle as the hosting (UI)view.
  wi.window_handle = s_render_view;
  wi.surface_width = static_cast<u32>(std::max(s_render_width, 1));
  wi.surface_height = static_cast<u32>(std::max(s_render_height, 1));
  wi.surface_scale = s_render_scale;
  return wi;
}

void Host::ReleaseRenderWindow()
{
}

void Host::FrameDone()
{
}

//////////////////////////////////////////////////////////////////////////
// Emulation control
//////////////////////////////////////////////////////////////////////////

void IOSHost::BootGame(const std::string& path)
{
  BootGameWithResume(path, false);
}

void IOSHost::BootGameWithResume(const std::string& path, bool load_resume_state)
{
  Host::RunOnCPUThread([path, load_resume_state]() {
    if (System::IsValid())
      System::ShutdownSystem(false);

    SystemBootParameters params(path);
    if (load_resume_state && !path.empty())
    {
      GameList::Entry entry;
      if (GameList::PopulateEntryFromPath(path, &entry) && !entry.serial.empty())
      {
        std::string resume = System::GetGameSaveStateFileName(entry.serial, -1);
        if (FileSystem::FileExists(resume.c_str()))
          params.save_state = std::move(resume);
      }
    }
    Error error;
    if (!System::BootSystem(std::move(params), &error))
      PostEvent(Event::Error, error.GetDescription());
  });
}

void IOSHost::SetPaused(bool paused)
{
  Host::RunOnCPUThread([paused]() {
    if (System::IsValid())
      System::PauseSystem(paused);
  });
}

void IOSHost::Reset()
{
  Host::RunOnCPUThread([]() {
    if (System::IsValid())
      System::ResetSystem();
  });
}

void IOSHost::Shutdown(bool save_resume_state)
{
  Host::RunOnCPUThread([save_resume_state]() {
    if (System::IsValid())
      System::ShutdownSystem(save_resume_state);
  });
}

bool IOSHost::IsSystemActive()
{
  return System::IsValid();
}

static std::string GetSlotPath(int slot)
{
  return System::GetGameSaveStateFileName(System::GetGameSerial(), slot);
}

void IOSHost::SaveStateToSlot(int slot)
{
  Host::RunOnCPUThread([slot]() {
    if (!System::IsValid())
      return;

    Error error;
    if (!System::SaveState(GetSlotPath(slot).c_str(), &error, true))
      PostEvent(Event::Error, error.GetDescription());
  });
}

void IOSHost::LoadStateFromSlot(int slot)
{
  Host::RunOnCPUThread([slot]() {
    if (!System::IsValid())
      return;

    Error error;
    if (!System::LoadState(GetSlotPath(slot).c_str(), &error, true))
      PostEvent(Event::Error, error.GetDescription());
  });
}

bool IOSHost::HasSaveStateInSlot(int slot)
{
  std::string path;
  Host::RunOnCPUThread([slot, &path]() {
    if (System::IsValid())
      path = GetSlotPath(slot);
  }, true);
  return !path.empty() && FileSystem::FileExists(path.c_str());
}

void IOSHost::SetPadButton(PadButton button, bool pressed)
{
  const u32 index = static_cast<u32>(button);
  Host::RunOnCPUThread([index, pressed]() {
    if (Controller* pad = System::GetController(0))
      pad->SetBindState(index, pressed ? 1.0f : 0.0f);
  });
}

void IOSHost::SetPadStick(int stick, float x, float y)
{
  // AnalogController binds: buttons first (Button::Count = 17), then half-axes LLeft..RUp.
  static constexpr u32 FIRST_HALF_AXIS = 17;
  const u32 base = FIRST_HALF_AXIS + (stick ? 4u : 0u);
  const float left = x < 0.0f ? -x : 0.0f, right = x > 0.0f ? x : 0.0f;
  const float up = y < 0.0f ? -y : 0.0f, down = y > 0.0f ? y : 0.0f;
  Host::RunOnCPUThread([base, left, right, up, down]() {
    if (Controller* pad = System::GetController(0))
    {
      pad->SetBindState(base + 0, left);
      pad->SetBindState(base + 1, right);
      pad->SetBindState(base + 2, down);
      pad->SetBindState(base + 3, up);
    }
  });
}

bool IOSHost::GetGameInfo(const std::string& path, GameInfo* info)
{
  GameList::Entry entry;
  if (!GameList::PopulateEntryFromPath(path, &entry))
    return false;

  info->title = entry.title;
  info->serial = entry.serial;
  info->region = Settings::GetDiscRegionName(entry.region);
  return true;
}

bool IOSHost::IsPaused()
{
  return System::IsPaused();
}

// Cached from Host::OnGameChanged so UI-thread queries never wait on the CPU thread
// (which may itself be waiting on the main thread while the Metal layer is created).
static std::mutex s_game_info_mutex;
static std::string s_cur_path, s_cur_serial, s_cur_title;

std::string IOSHost::GetCurrentGamePath()
{
  std::unique_lock lock(s_game_info_mutex);
  return s_cur_path;
}

std::string IOSHost::GetCurrentGameSerial()
{
  std::unique_lock lock(s_game_info_mutex);
  return s_cur_serial;
}

std::string IOSHost::GetCurrentGameTitle()
{
  std::unique_lock lock(s_game_info_mutex);
  return s_cur_title;
}

std::string IOSHost::GetSaveStatePathForSlot(int slot)
{
  const std::string serial = GetCurrentGameSerial();
  return serial.empty() ? std::string() : System::GetGameSaveStateFileName(serial, slot);
}

std::string IOSHost::GetSaveStatePathForSerial(const std::string& serial, int slot)
{
  return serial.empty() ? std::string() : System::GetGameSaveStateFileName(serial, slot);
}

bool IOSHost::SaveStateToPathSync(const std::string& path)
{
  bool ok = false;
  Host::RunOnCPUThread([&path, &ok]() {
    if (!System::IsValid())
      return;
    Error error;
    ok = System::SaveState(path.c_str(), &error, true);
    if (!ok)
      ERROR_LOG("Save state failed: {}", error.GetDescription());
  }, true);
  return ok;
}

bool IOSHost::SaveResumeState()
{
  const std::string path = GetSaveStatePathForSlot(-1);
  return !path.empty() && SaveStateToPathSync(path);
}

bool IOSHost::SaveStateToSlotSync(int slot)
{
  const std::string path = GetSaveStatePathForSlot(slot);
  return !path.empty() && SaveStateToPathSync(path);
}

bool IOSHost::LoadStateFromPathSync(const std::string& path)
{
  bool ok = false;
  Host::RunOnCPUThread([&path, &ok]() {
    if (!System::IsValid() || !FileSystem::FileExists(path.c_str()))
      return;
    Error error;
    ok = System::LoadState(path.c_str(), &error, true);
    if (!ok)
      ERROR_LOG("Load state failed: {}", error.GetDescription());
  }, true);
  return ok;
}

bool IOSHost::LoadStateFromSlotSync(int slot)
{
  const std::string path = GetSaveStatePathForSlot(slot);
  return !path.empty() && LoadStateFromPathSync(path);
}

//////////////////////////////////////////////////////////////////////////
// Settings
//////////////////////////////////////////////////////////////////////////

int IOSHost::GetIntSetting(const char* section, const char* key, int default_value)
{
  return Host::GetBaseIntSettingValue(section, key, default_value);
}

bool IOSHost::GetBoolSetting(const char* section, const char* key, bool default_value)
{
  return Host::GetBaseBoolSettingValue(section, key, default_value);
}

std::string IOSHost::GetStringSetting(const char* section, const char* key, const char* default_value)
{
  return Host::GetBaseStringSettingValue(section, key, default_value);
}

void IOSHost::SetIntSetting(const char* section, const char* key, int value)
{
  Host::SetBaseIntSettingValue(section, key, value);
}

void IOSHost::SetBoolSetting(const char* section, const char* key, bool value)
{
  Host::SetBaseBoolSettingValue(section, key, value);
}

void IOSHost::SetStringSetting(const char* section, const char* key, const char* value)
{
  Host::SetBaseStringSettingValue(section, key, value);
}

float IOSHost::GetFloatSetting(const char* section, const char* key, float default_value)
{
  return Host::GetBaseFloatSettingValue(section, key, default_value);
}

void IOSHost::SetFloatSetting(const char* section, const char* key, float value)
{
  Host::SetBaseFloatSettingValue(section, key, value);
}

void IOSHost::SetFloatSettingRuntime(const char* section, const char* key, float value)
{
  Host::SetBaseFloatSettingValue(section, key, value);
  Host::RunOnCPUThread([]() { System::ApplySettings(false); });
}

void IOSHost::ClearSettingsSection(const char* section)
{
  auto lock = Host::GetSettingsLock();
  if (s_settings)
    s_settings->ClearSection(section);
}

std::vector<unsigned char> IOSHost::GetSaveStatePreviewPNG(const std::string& path)
{
  std::optional<ExtendedSaveStateInfo> info = System::GetExtendedSaveStateInfo(path.c_str());
  if (!info.has_value() || !info->screenshot.IsValid())
    return {};

  std::optional<std::vector<u8>> png = info->screenshot.SaveToBuffer("preview.png");
  return png.has_value() ? std::vector<unsigned char>(png->begin(), png->end()) : std::vector<unsigned char>();
}

std::vector<IOSHost::BIOSInfo> IOSHost::ListBIOSImages()
{
  std::vector<BIOSInfo> ret;
  for (const auto& [path, image] : BIOS::FindBIOSImagesInDirectory(EmuFolders::Bios.c_str()))
  {
    BIOSInfo bi;
    bi.path = path;
    bi.file_name = std::string(Path::GetFileName(path));
    bi.valid = (image != nullptr);
    bi.description = image ? image->description : "Unknown BIOS";
    bi.region = image ? Settings::GetConsoleRegionName(image->region) : "";
    bi.country_code = !image ? "" :
                      (image->region == ConsoleRegion::NTSC_J ? "JP" :
                                                                 (image->region == ConsoleRegion::PAL ? "EU" : "US"));
    ret.push_back(std::move(bi));
  }
  return ret;
}

void IOSHost::CommitSettings()
{
  Host::CommitBaseSettingChanges();
  Host::RunOnCPUThread([]() { System::ApplySettings(false); });
}

//////////////////////////////////////////////////////////////////////////
// Host interface
//////////////////////////////////////////////////////////////////////////

void Host::ReportFatalError(std::string_view title, std::string_view message)
{
  ERROR_LOG("ReportFatalError: {}: {}", title, message);
  IOSHost::PostEvent(IOSHost::Event::Error, std::string(message));
}

void Host::ReportErrorAsync(std::string_view title, std::string_view message)
{
  ERROR_LOG("ReportErrorAsync: {}: {}", title, message);
  if (!message.empty())
    IOSHost::PostEvent(IOSHost::Event::Error, std::string(message));
}

bool Host::ConfirmMessage(std::string_view title, std::string_view message)
{
  INFO_LOG("ConfirmMessage: {}: {}", title, message);
  return true;
}

void Host::ReportDebuggerMessage(std::string_view message)
{
  INFO_LOG("ReportDebuggerMessage: {}", message);
}

std::span<const std::pair<const char*, const char*>> Host::GetAvailableLanguageList()
{
  return {};
}

bool Host::ChangeLanguage(const char* new_language)
{
  return false;
}

s32 Host::Internal::GetTranslatedStringImpl(std::string_view context, std::string_view msg, char* tbuf,
                                            size_t tbuf_space)
{
  if (msg.size() > tbuf_space)
    return -1;
  else if (msg.empty())
    return 0;

  std::memcpy(tbuf, msg.data(), msg.size());
  return static_cast<s32>(msg.size());
}

std::string Host::TranslatePluralToString(const char* context, const char* msg, const char* disambiguation, int count)
{
  std::string ret(msg);
  const std::string count_str = std::to_string(count);
  for (std::string::size_type pos = ret.find("%n"); pos != std::string::npos; pos = ret.find("%n"))
    ret.replace(pos, 2, count_str);
  return ret;
}

SmallString Host::TranslatePluralToSmallString(const char* context, const char* msg, const char* disambiguation,
                                               int count)
{
  SmallString ret(msg);
  ret.replace("%n", TinyString::from_format("{}", count));
  return ret;
}

void Host::LoadSettings(SettingsInterface& si, std::unique_lock<std::mutex>& lock)
{
}

void Host::CheckForSettingsChanges(const Settings& old_settings)
{
}

void Host::CommitBaseSettingChanges()
{
  auto lock = Host::GetSettingsLock();
  if (s_settings)
    s_settings->Save();
}

bool Host::ResourceFileExists(std::string_view filename, bool allow_override)
{
  const std::string path(Path::Combine(EmuFolders::Resources, filename));
  return FileSystem::FileExists(path.c_str());
}

std::optional<DynamicHeapArray<u8>> Host::ReadResourceFile(std::string_view filename, bool allow_override)
{
  const std::string path(Path::Combine(EmuFolders::Resources, filename));
  std::optional<DynamicHeapArray<u8>> ret(FileSystem::ReadBinaryFile(path.c_str()));
  if (!ret.has_value())
    ERROR_LOG("Failed to read resource file '{}'", filename);
  return ret;
}

std::optional<std::string> Host::ReadResourceFileToString(std::string_view filename, bool allow_override)
{
  const std::string path(Path::Combine(EmuFolders::Resources, filename));
  std::optional<std::string> ret(FileSystem::ReadFileToString(path.c_str()));
  if (!ret.has_value())
    ERROR_LOG("Failed to read resource file to string '{}'", filename);
  return ret;
}

std::optional<std::time_t> Host::GetResourceFileTimestamp(std::string_view filename, bool allow_override)
{
  const std::string path(Path::Combine(EmuFolders::Resources, filename));
  FILESYSTEM_STAT_DATA sd;
  if (!FileSystem::StatFile(path.c_str(), &sd))
    return std::nullopt;

  return sd.ModificationTime;
}

void Host::OnSystemStarting()
{
}

void Host::OnSystemStarted()
{
  PlatformMisc::SuspendScreensaver();
  IOSHost::PostEvent(IOSHost::Event::Started);
}

void Host::OnSystemDestroyed()
{
  {
    std::unique_lock lock(s_game_info_mutex);
    s_cur_path.clear();
    s_cur_serial.clear();
    s_cur_title.clear();
  }
  PlatformMisc::ResumeScreensaver();
  IOSHost::PostEvent(IOSHost::Event::Stopped);
}

void Host::OnSystemPaused()
{
  IOSHost::PostEvent(IOSHost::Event::Paused);
}

void Host::OnSystemResumed()
{
  IOSHost::PostEvent(IOSHost::Event::Resumed);
}

void Host::OnIdleStateChanged()
{
}

void Host::OnPerformanceCountersUpdated()
{
}

void Host::OnGameChanged(const std::string& disc_path, const std::string& game_serial, const std::string& game_name)
{
  INFO_LOG("Game: {} [{}] ({})", game_name, game_serial, disc_path);
  std::unique_lock lock(s_game_info_mutex);
  s_cur_path = disc_path;
  s_cur_serial = game_serial;
  s_cur_title = game_name;
}

void Host::OnMediaCaptureStarted()
{
}

void Host::OnMediaCaptureStopped()
{
}

void Host::RequestResizeHostDisplay(s32 width, s32 height)
{
}

void Host::RequestExitApplication(bool save_state_if_running)
{
}

void Host::RequestExitBigPicture()
{
}

void Host::RequestSystemShutdown(bool allow_confirm, bool save_state)
{
  if (System::IsValid())
    System::ShutdownSystem(save_state);
}

bool Host::IsFullscreen()
{
  return true;
}

void Host::SetFullscreen(bool enabled)
{
}

void Host::OpenURL(std::string_view url)
{
  NSString* str = [[NSString alloc] initWithBytes:url.data() length:url.size() encoding:NSUTF8StringEncoding];
  INFO_LOG("OpenURL: {}", [str UTF8String]);
}

bool Host::CopyTextToClipboard(std::string_view text)
{
  return false;
}

void Host::SetMouseMode(bool relative, bool hide_cursor)
{
}

void Host::OnAchievementsLoginRequested(Achievements::LoginRequestReason reason)
{
}

void Host::OnAchievementsLoginSuccess(const char* username, u32 points, u32 sc_points, u32 unread_messages)
{
}

void Host::OnAchievementsRefreshed()
{
}

void Host::OnAchievementsHardcoreModeChanged(bool enabled)
{
}

void Host::OnCoverDownloaderOpenRequested()
{
}

bool Host::ShouldPreferHostFileSelector()
{
  return false;
}

void Host::OpenHostFileSelectorAsync(std::string_view title, bool select_directory, FileSelectorCallback callback,
                                     FileSelectorFilters filters /* = FileSelectorFilters() */,
                                     std::string_view initial_directory /* = std::string_view() */)
{
  callback(std::string());
}

std::optional<u32> InputManager::ConvertHostKeyboardStringToCode(std::string_view str)
{
  return std::nullopt;
}

std::optional<std::string> InputManager::ConvertHostKeyboardCodeToString(u32 code)
{
  return std::nullopt;
}

const char* InputManager::ConvertHostKeyboardCodeToIcon(u32 code)
{
  return nullptr;
}

void Host::AddFixedInputBindings(SettingsInterface& si)
{
}

void Host::OnInputDeviceConnected(std::string_view identifier, std::string_view device_name)
{
  INFO_LOG("Controller connected: {} ({})", identifier, device_name);

  // Map the first physical controller to port 1 automatically.
  const std::string id(identifier);
  Host::RunOnCPUThread([id]() {
    const std::vector<std::pair<GenericInputBinding, std::string>> mapping = InputManager::GetGenericBindingMapping(id);
    if (mapping.empty())
      return;

    auto lock = Host::GetSettingsLock();
    SettingsInterface* si = Host::GetSettingsInterface();
    if (!InputManager::MapController(*si, 0, mapping))
      return;

    if (s_settings)
      s_settings->Save();
    InputManager::ReloadBindings(*si, *si);
  });
}

void Host::OnInputDeviceDisconnected(InputBindingKey key, std::string_view identifier)
{
  INFO_LOG("Controller disconnected: {}", identifier);
}

std::optional<WindowInfo> Host::GetTopLevelWindowInfo()
{
  return std::nullopt;
}

void Host::RefreshGameListAsync(bool invalidate_cache)
{
}

void Host::CancelGameListRefresh()
{
}

BEGIN_HOTKEY_LIST(g_host_hotkeys)
END_HOTKEY_LIST()
