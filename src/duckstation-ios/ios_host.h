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
void SetPaused(bool paused);
void Reset();
void Shutdown(bool save_resume_state);
bool IsSystemActive();

void SaveStateToSlot(int slot);
void LoadStateFromSlot(int slot);
bool HasSaveStateInSlot(int slot);

void SetPadButton(PadButton button, bool pressed);

// Settings (persisted to settings.ini in Documents).
int GetIntSetting(const char* section, const char* key, int default_value);
bool GetBoolSetting(const char* section, const char* key, bool default_value);
std::string GetStringSetting(const char* section, const char* key, const char* default_value);
void SetIntSetting(const char* section, const char* key, int value);
void SetBoolSetting(const char* section, const char* key, bool value);
void SetStringSetting(const char* section, const char* key, const char* value);

/// Writes settings to disk and applies them to a running game.
void CommitSettings();

} // namespace IOSHost
