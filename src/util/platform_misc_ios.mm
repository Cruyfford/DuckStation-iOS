// SPDX-FileCopyrightText: 2019-2024 Connor McLaughlin <stenzek@gmail.com>, 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// iOS implementation of the platform helpers (UIKit instead of Cocoa/IOKit).

#include <UIKit/UIKit.h>
#include <QuartzCore/QuartzCore.h>
#include <optional>
#include <sys/sysctl.h>
#include <unistd.h>

#include "metal_layer.h"
#include "platform_misc.h"
#include "window_info.h"

#include "common/log.h"

Log_SetChannel(PlatformMisc);

#if __has_feature(objc_arc)
#error ARC should not be enabled.
#endif

bool PlatformMisc::InitializeSocketSupport(Error* error)
{
  return true;
}

static void SetIdleTimerDisabled(bool disabled)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[UIApplication sharedApplication] setIdleTimerDisabled:disabled ? YES : NO];
  });
}

void PlatformMisc::SuspendScreensaver()
{
  SetIdleTimerDisabled(true);
}

void PlatformMisc::ResumeScreensaver()
{
  SetIdleTimerDisabled(false);
}

size_t PlatformMisc::GetRuntimePageSize()
{
  return static_cast<size_t>(getpagesize());
}

bool PlatformMisc::PlaySoundAsync(const char* path)
{
  // Not used on iOS (achievement sounds); silently succeed.
  return true;
}

bool CocoaTools::CreateMetalLayer(WindowInfo* wi)
{
  // Only used by the Vulkan swap chain, which is disabled on iOS.
  return false;
}

void CocoaTools::DestroyMetalLayer(WindowInfo* wi)
{
}

std::optional<float> CocoaTools::GetViewRefreshRate(const WindowInfo& wi)
{
  if (![NSThread isMainThread])
  {
    std::optional<float> ret;
    dispatch_sync(dispatch_get_main_queue(), [&ret, wi] { ret = GetViewRefreshRate(wi); });
    return ret;
  }

  UIView* const view = (__bridge UIView*)wi.window_handle;
  UIScreen* screen = (view && [view window]) ? [[view window] screen] : [UIScreen mainScreen];
  const NSInteger fps = [screen maximumFramesPerSecond];
  if (fps <= 0)
    return std::nullopt;

  return static_cast<float>(fps);
}
