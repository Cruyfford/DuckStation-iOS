// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

#pragma once

#include <string>
#include <vector>

// Bridge between the UIKit frontend and the DuckStation core.
// All functions are safe to call from the main (UI) thread.
namespace IOSHost {

enum class Event : int
{
  Started = 1,
  Stopped = 2,
  Paused = 3,
  Resumed = 4,
  Error = 5,
};

// Called on the main thread.
using EventCallback = void (*)(Event event, const char* message);

// PlayStation pad buttons, matching the core's controller bind indices.
enum class PadButton : int
{
  Select = 0,
  L3 = 1,
  R3 = 2,
  Start = 3,
  Up = 4,
  Right = 5,
  Down = 6,
  Left = 7,
  L2 = 8,
  R2 = 9,
  L1 = 10,
  R1 = 11,
  Triangle = 12,
  Circle = 13,
  Cross = 14,
  Square = 15,
};

/// Sets up folders/settings and starts the emulation thread. Call once at launch.
bool Initialize(const std::string& documents_dir, const std::string& bundle_dir, std::string* error);
void SetEventCallback(EventCallback callback);

std::string GetGamesDirectory();
std::string GetBIOSDirectory();
bool HasBIOS();
std::vector<std::string> ScanGames();

/// The UIView (passed as void*) the Metal layer is attached to. Sizes are in pixels.
void SetRenderView(void* view, int width_px, int height_px, float scale);
void ResizeRenderView(int width_px, int height_px, float scale);
void ClearRenderView();

void BootGame(const std::string& path);
/// Boots, optionally restoring the game's resume state (saved when leaving the game).
void BootGameWithResume(const std::string& path, bool load_resume_state);
void SetPaused(bool paused);
void Reset();
void Shutdown(bool save_resume_state);
bool IsSystemActive();

void SaveStateToSlot(int slot);
void LoadStateFromSlot(int slot);
bool HasSaveStateInSlot(int slot);

void SetPadButton(PadButton button, bool pressed);
/// Analog sticks, x/y in [-1, 1] (y up is negative, like SDL). stick 0 = left, 1 = right.
void SetPadStick(int stick, float x, float y);

struct GameInfo
{
  std::string title;
  std::string serial;
  std::string region;
};
/// Reads title/serial/region from a disc image (no system needed).
bool GetGameInfo(const std::string& path, GameInfo* info);

bool IsPaused();
std::string GetCurrentGamePath();
std::string GetCurrentGameSerial();
std::string GetCurrentGameTitle();

/// Save state file for a slot of the running game (empty when no game). Slot -1 = resume state.
std::string GetSaveStatePathForSlot(int slot);
/// Same, for a game that isn't running, by serial.
std::string GetSaveStatePathForSerial(const std::string& serial, int slot);
/// Saves the resume state of the running game (blocking). Returns success.
bool SaveResumeState();
/// Synchronous save/load used by the bridge's completion-based API. Returns success.
bool SaveStateToSlotSync(int slot);
bool LoadStateFromSlotSync(int slot);
bool LoadStateFromPathSync(const std::string& path);
bool SaveStateToPathSync(const std::string& path);
/// PNG-encoded screenshot stored in a save state (empty if none).
std::vector<unsigned char> GetSaveStatePreviewPNG(const std::string& path);

struct BIOSInfo
{
  std::string file_name;
  std::string path;
  std::string region;
  std::string country_code;
  std::string description;
  bool valid;
};
std::vector<BIOSInfo> ListBIOSImages();

// Settings (persisted to settings.ini in Documents).
int GetIntSetting(const char* section, const char* key, int default_value);
bool GetBoolSetting(const char* section, const char* key, bool default_value);
std::string GetStringSetting(const char* section, const char* key, const char* default_value);
void SetIntSetting(const char* section, const char* key, int value);
void SetBoolSetting(const char* section, const char* key, bool value);
void SetStringSetting(const char* section, const char* key, const char* value);
float GetFloatSetting(const char* section, const char* key, float default_value);
void SetFloatSetting(const char* section, const char* key, float value);
/// Sets a value and applies it to the running game immediately.
void SetFloatSettingRuntime(const char* section, const char* key, float value);
void ClearSettingsSection(const char* section);

/// Writes settings to disk and applies them to a running game.
void CommitSettings();

} // namespace IOSHost
