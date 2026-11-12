// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// App shell for the ARMSX2-derived SwiftUI frontend running DuckStation:
// app/scene delegates, the window hosting SwiftUI, and core-event forwarding.

#import <UIKit/UIKit.h>
#import <objc/message.h>

#include "../../ios_host.h"

#include <string>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

void DSBridgeHandleHostEvent(int event);

static NSString* const kSwiftUIHostClass = @"DuckStation.SwiftUIHost";

static UIViewController* DSCreateMenuController()
{
  Class host = NSClassFromString(kSwiftUIHostClass);
  SEL sel = NSSelectorFromString(@"createMenuController");
  if (!host || ![host respondsToSelector:sel])
  {
    NSLog(@"[DuckStation] SwiftUIHost not found");
    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;
    return vc;
  }
  return ((UIViewController * (*)(id, SEL)) objc_msgSend)(host, sel);
}

static void DSHostEvent(IOSHost::Event event, const char* message)
{
  if (event == IOSHost::Event::Error)
    NSLog(@"[DuckStation] %s", message ? message : "");

  DSBridgeHandleHostEvent(static_cast<int>(event));

  // A failed boot never sends Started/Stopped; send the menu home so it doesn't wait on a black screen.
  if (event == IOSHost::Event::Error && !IOSHost::IsSystemActive())
    DSBridgeHandleHostEvent(static_cast<int>(IOSHost::Event::Stopped));
}

//////////////////////////////////////////////////////////////////////////
// Scene delegate
//////////////////////////////////////////////////////////////////////////

@interface DSSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation DSSceneDelegate
{
  BOOL _pausedForBackground;
}

- (void)scene:(UIScene*)scene
  willConnectToSession:(UISceneSession*)session
               options:(UISceneConnectionOptions*)connectionOptions
{
  UIWindowScene* windowScene = (UIWindowScene*)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.backgroundColor = UIColor.blackColor;
  self.window.rootViewController = DSCreateMenuController();
  [self.window makeKeyAndVisible];
}

- (void)sceneWillResignActive:(UIScene*)scene
{
  // Metal can't present in the background; pause and resume only if we were the ones who paused.
  if (IOSHost::IsSystemActive() && !IOSHost::IsPaused())
  {
    _pausedForBackground = YES;
    IOSHost::SetPaused(true);
  }
}

- (void)sceneDidBecomeActive:(UIScene*)scene
{
  if (_pausedForBackground)
  {
    _pausedForBackground = NO;
    if (IOSHost::IsSystemActive())
      IOSHost::SetPaused(false);
  }
}

- (void)sceneDidEnterBackground:(UIScene*)scene
{
  // Memory cards are flushed by the core; keep the settings file current too.
  IOSHost::CommitSettings();
}

@end

//////////////////////////////////////////////////////////////////////////
// App delegate
//////////////////////////////////////////////////////////////////////////

@interface DSAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation DSAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* bundle = NSBundle.mainBundle.bundlePath;

  // Earlier builds imported into ARMSX2's lowercase folders; move those files where DuckStation looks.
  NSFileManager* fm = NSFileManager.defaultManager;
  const struct { NSString* from; NSString* to; } moves[] = {{@"bios", @"BIOS"}, {@"iso", @"Games"}};
  for (const auto& m : moves)
  {
    NSString* from = [documents stringByAppendingPathComponent:m.from];
    NSString* to = [documents stringByAppendingPathComponent:m.to];
    NSArray<NSString*>* files = [fm contentsOfDirectoryAtPath:from error:nil];
    if (!files)
      continue;
    [fm createDirectoryAtPath:to withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString* f in files)
    {
      NSString* dst = [to stringByAppendingPathComponent:f];
      if (![fm fileExistsAtPath:dst])
        [fm moveItemAtPath:[from stringByAppendingPathComponent:f] toPath:dst error:nil];
    }
    if ([fm contentsOfDirectoryAtPath:from error:nil].count == 0)
      [fm removeItemAtPath:from error:nil];
  }

  IOSHost::SetEventCallback(&DSHostEvent);
  std::string error;
  if (!IOSHost::Initialize(std::string(documents.fileSystemRepresentation),
                           std::string(bundle.fileSystemRepresentation), &error))
  {
    NSLog(@"[DuckStation] Initialization failed: %s", error.c_str());
  }
  return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
  configurationForConnectingSceneSession:(UISceneSession*)connectingSceneSession
                                 options:(UISceneConnectionOptions*)options
{
  UISceneConfiguration* config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                sessionRole:connectingSceneSession.role];
  config.delegateClass = [DSSceneDelegate class];
  return config;
}

@end

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([DSAppDelegate class]));
  }
}
