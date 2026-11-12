// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// ARMSX2Bridge implemented on top of DuckStation (PS1), so the ARMSX2 SwiftUI frontend can drive it.
// Anything not implemented here gets a default from the generated ARMSX2Bridge+Stubs.mm.

#import "ARMSX2Bridge.h"

#include "../../ios_host.h"

#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>
#include <iterator>
#include <string>
#include <vector>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

//////////////////////////////////////////////////////////////////////////
// Helpers
//////////////////////////////////////////////////////////////////////////

static NSString* DSString(const std::string& s)
{
  return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static std::string DSStd(NSString* s)
{
  return s ? std::string(s.UTF8String ?: "") : std::string();
}

static NSString* const kFavoritesKey = @"DSFavoriteGames";
static NSString* const kDefaultBIOSKey = @"DSDefaultBIOS";

static NSSet<NSString*>* DSGameExtensions()
{
  static NSSet<NSString*>* set =
    [NSSet setWithArray:@[ @"cue", @"chd", @"pbp", @"m3u", @"iso", @"img", @"ecm", @"mds", @"bin", @"exe", @"psexe",
                           @"psf" ]];
  return set;
}

// ARMSX2 slot numbers -> DuckStation: auto (-2) = resume state, quick (0) = slot 11, 1..10 as is.
static int DSSlotFromARMSX2(NSInteger slot)
{
  if (slot == -2)
    return -1;
  if (slot == 0)
    return 11;
  return static_cast<int>(slot);
}

static NSString* DSResolveGamePath(NSString* isoName)
{
  if (isoName.length == 0)
    return nil;
  if (isoName.isAbsolutePath)
    return [[NSFileManager defaultManager] fileExistsAtPath:isoName] ? isoName : nil;

  NSString* games = DSString(IOSHost::GetGamesDirectory());
  NSString* candidate = [games stringByAppendingPathComponent:isoName];
  if ([[NSFileManager defaultManager] fileExistsAtPath:candidate])
    return candidate;

  NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  candidate = [docs stringByAppendingPathComponent:isoName];
  return [[NSFileManager defaultManager] fileExistsAtPath:candidate] ? candidate : nil;
}

static void DSPost(NSString* name, NSDictionary* userInfo = nil)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:userInfo];
  });
}

//////////////////////////////////////////////////////////////////////////
// Render view: hosts the CAMetalLayer the core creates; resizes the swap chain on layout.
//////////////////////////////////////////////////////////////////////////

@interface DSGameRenderView : UIView
- (CGSize)pixelSize;
- (CGFloat)pixelScale;
@end

@implementation DSGameRenderView
{
  CGSize _lastPixelSize;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    self.backgroundColor = UIColor.blackColor;
    self.opaque = YES;
    self.multipleTouchEnabled = YES;
  }
  return self;
}

- (CGFloat)pixelScale
{
  UIScreen* screen = self.window.windowScene.screen ?: UIScreen.mainScreen;
  return screen.nativeScale;
}

- (CGSize)pixelSize
{
  const CGFloat scale = [self pixelScale];
  return CGSizeMake(std::floor(self.bounds.size.width * scale), std::floor(self.bounds.size.height * scale));
}

- (void)layoutSubviews
{
  [super layoutSubviews];

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (CALayer* sub in self.layer.sublayers)
  {
    if ([sub isKindOfClass:[CAMetalLayer class]])
      sub.frame = self.bounds;
  }
  [CATransaction commit];

  const CGSize px = [self pixelSize];
  if (px.width <= 0 || px.height <= 0 || CGSizeEqualToSize(px, _lastPixelSize))
    return;

  _lastPixelSize = px;
  IOSHost::ResizeRenderView(static_cast<int>(px.width), static_cast<int>(px.height),
                            static_cast<float>([self pixelScale]));
}

@end

static DSGameRenderView* DSRenderView()
{
  static DSGameRenderView* view = [[DSGameRenderView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  return view;
}

/// Gives the core the render view and its current size. Called right before booting.
static void DSAttachRenderView()
{
  DSGameRenderView* view = DSRenderView();
  CGSize px = [view pixelSize];
  if (px.width <= 0 || px.height <= 0)
  {
    const CGFloat scale = UIScreen.mainScreen.nativeScale;
    px = CGSizeMake(UIScreen.mainScreen.bounds.size.width * scale, UIScreen.mainScreen.bounds.size.height * scale);
  }
  IOSHost::SetRenderView((__bridge void*)view, static_cast<int>(px.width), static_cast<int>(px.height),
                         static_cast<float>([view pixelScale]));
}

//////////////////////////////////////////////////////////////////////////
// Value classes
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2SaveStateSlotInfo
@end

@implementation ARMSX2BIOSInfo
@end

@implementation ARMSX2RetroAchievementsToastInfo
@end

//////////////////////////////////////////////////////////////////////////
// Core: games
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge

+ (nullable NSString*)currentISOPath
{
  const std::string path = IOSHost::GetCurrentGamePath();
  if (!path.empty())
    return DSString(path);

  NSString* boot = DSString(IOSHost::GetStringSetting("GameISO", "BootISO", ""));
  return boot.length > 0 ? boot : nil;
}

+ (nullable NSString*)currentGameISOName
{
  NSString* path = [self currentISOPath];
  return path.length > 0 ? path.lastPathComponent : nil;
}

+ (nullable NSString*)discInDriveName
{
  const std::string path = IOSHost::GetCurrentGamePath();
  return path.empty() ? nil : DSString(path).lastPathComponent;
}

+ (nonnull NSString*)isoDirectory
{
  return DSString(IOSHost::GetGamesDirectory());
}

+ (nonnull NSString*)documentsDirectory
{
  return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

+ (nonnull NSArray<NSString*>*)availableISOs
{
  NSMutableArray<NSString*>* names = [NSMutableArray array];
  NSString* games = [self isoDirectory];
  for (const std::string& path : IOSHost::ScanGames())
  {
    NSString* full = DSString(path);
    NSString* rel = [full hasPrefix:games] ? [full substringFromIndex:games.length + 1] : full.lastPathComponent;
    [names addObject:rel];
  }
  return names;
}

+ (nonnull NSArray<NSDictionary<NSString*, id>*>*)availableISOEntries
{
  NSMutableArray* entries = [NSMutableArray array];
  NSString* games = [self isoDirectory];
  for (const std::string& path : IOSHost::ScanGames())
  {
    NSString* full = DSString(path);
    NSString* rel = [full hasPrefix:games] ? [full substringFromIndex:games.length + 1] : full.lastPathComponent;
    [entries addObject:@{ @"name" : rel, @"path" : full, @"external" : @NO, @"source" : @"On My iPhone" }];
  }
  return entries;
}

+ (nonnull NSDictionary<NSString*, NSString*>*)gameMetadataForISO:(nonnull NSString*)isoName
{
  NSString* path = DSResolveGamePath(isoName);
  NSString* fileName = (path ?: isoName).lastPathComponent;
  NSMutableDictionary* md = [NSMutableDictionary dictionary];
  md[@"fileTitle"] = fileName.stringByDeletingPathExtension ?: fileName;
  if (!path)
    return md;

  IOSHost::GameInfo info;
  if (IOSHost::GetGameInfo(DSStd(path), &info))
  {
    if (!info.title.empty())
      md[@"title"] = DSString(info.title);
    if (!info.serial.empty())
      md[@"serial"] = DSString(info.serial);
    if (!info.region.empty())
      md[@"region"] = DSString(info.region);
  }
  return md;
}

+ (nullable NSString*)linkedDiscPathForELF:(nonnull NSString*)elfName
{
  return nil;
}

+ (void)setLinkedDiscPath:(nullable NSString*)discPath forELF:(nonnull NSString*)elfName
{
}

+ (nonnull NSString*)clearCacheForISO:(nonnull NSString*)isoName
{
  return @"";
}

+ (nonnull NSString*)deleteGameDataForISO:(nonnull NSString*)isoName
{
  NSString* path = DSResolveGamePath(isoName);
  IOSHost::GameInfo info;
  if (!path || !IOSHost::GetGameInfo(DSStd(path), &info) || info.serial.empty())
    return @"";

  int removed = 0;
  for (int slot = -1; slot <= 11; slot++)
  {
    const std::string state = IOSHost::GetSaveStatePathForSerial(info.serial, slot);
    if (!state.empty() && [[NSFileManager defaultManager] removeItemAtPath:DSString(state) error:nil])
      removed++;
  }
  return [NSString stringWithFormat:@"%d", removed];
}

+ (BOOL)deleteISO:(nonnull NSString*)isoName deleteGameData:(BOOL)deleteGameData
{
  NSString* path = DSResolveGamePath(isoName);
  if (!path)
    return NO;
  if (deleteGameData)
    [self deleteGameDataForISO:isoName];

  NSFileManager* fm = [NSFileManager defaultManager];
  // A .cue references its .bin tracks; delete those too.
  if ([path.pathExtension.lowercaseString isEqualToString:@"cue"])
  {
    NSString* cue = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:@"FILE\\s+\"([^\"]+)\""
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    for (NSTextCheckingResult* m in [re matchesInString:cue options:0 range:NSMakeRange(0, cue.length)])
    {
      NSString* track = [path.stringByDeletingLastPathComponent
        stringByAppendingPathComponent:[cue substringWithRange:[m rangeAtIndex:1]]];
      [fm removeItemAtPath:track error:nil];
    }
  }
  return [fm removeItemAtPath:path error:nil];
}

+ (void)changeDiscToISO:(nonnull NSString*)isoName completion:(nullable ARMSX2SaveStateCompletion)completion
{
  // Disc swap for multi-disc games: reboot into the new disc keeping nothing else; .m3u handles most cases.
  if (completion)
    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
}

+ (void)ejectDiscWithCompletion:(nullable ARMSX2SaveStateCompletion)completion
{
  if (completion)
    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
}

+ (BOOL)canResolveISO:(nonnull NSString*)isoName
{
  return DSResolveGamePath(isoName) != nil;
}

+ (void)bootISO:(nonnull NSString*)isoName
{
  NSString* path = DSResolveGamePath(isoName) ?: isoName;
  IOSHost::SetStringSetting("GameISO", "BootISO", path.UTF8String);
}

+ (BOOL)isFavorite:(nonnull NSString*)isoName
{
  NSArray* favs = [[NSUserDefaults standardUserDefaults] arrayForKey:kFavoritesKey] ?: @[];
  return [favs containsObject:isoName];
}

+ (void)setFavorite:(nonnull NSString*)isoName favorite:(BOOL)favorite
{
  NSMutableArray* favs = [[[NSUserDefaults standardUserDefaults] arrayForKey:kFavoritesKey] ?: @[] mutableCopy];
  [favs removeObject:isoName];
  if (favorite)
    [favs addObject:isoName];
  [[NSUserDefaults standardUserDefaults] setObject:favs forKey:kFavoritesKey];
}

@end

//////////////////////////////////////////////////////////////////////////
// Input
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSInput)

+ (void)setPadButton:(ARMSX2PadButton)button pressed:(BOOL)pressed
{
  using PB = IOSHost::PadButton;
  static constexpr PB map[] = {PB::Up,     PB::Down,     PB::Left,   PB::Right, PB::Cross, PB::Circle,
                               PB::Square, PB::Triangle, PB::L1,     PB::R1,    PB::L2,    PB::R2,
                               PB::Start,  PB::Select,   PB::L3,     PB::R3};
  if (button < 0 || button >= static_cast<NSInteger>(std::size(map)))
    return;
  IOSHost::SetPadButton(map[button], pressed);
}

+ (void)setLeftStickX:(float)x Y:(float)y
{
  IOSHost::SetPadStick(0, x, y);
}

+ (void)setRightStickX:(float)x Y:(float)y
{
  IOSHost::SetPadStick(1, x, y);
}

+ (void)triggerDeviceHapticLarge:(NSUInteger)large small:(NSUInteger)small
{
}

@end

//////////////////////////////////////////////////////////////////////////
// VM lifecycle
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSVM)

+ (nonnull UIView*)gameRenderView
{
  return DSRenderView();
}

+ (void)prepareGameRenderViewForCurrentRenderer
{
  (void)DSRenderView();
}

+ (void)requestVMStop
{
  IOSHost::Shutdown(false);
}

+ (void)setVMPaused:(BOOL)paused
{
  IOSHost::SetPaused(paused);
}

+ (void)setFullScreen:(BOOL)enabled
{
}

+ (BOOL)isSDLFullscreen
{
  return YES;
}

+ (nonnull NSString*)buildVersion
{
  NSString* v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  return [NSString stringWithFormat:@"DuckStation iOS %@", v ?: @""];
}

// PS1 runs at full speed on the (cached) interpreter: no JIT needed, so never block booting on it.
+ (BOOL)isJITAvailable
{
  return YES;
}

+ (BOOL)isNoJITFallbackActive
{
  return NO;
}

+ (BOOL)isIdleVMPrewarmResolved
{
  return YES;
}

+ (BOOL)isEmulationOnlyModeActive
{
  return NO;
}

+ (int)limiterMode
{
  return 0;
}

+ (void)setRuntimeFastForwardEnabled:(BOOL)enabled speedPercent:(int)percent
{
  const float speed = enabled ? std::max(percent, 100) / 100.0f : 1.0f;
  IOSHost::SetFloatSettingRuntime("Main", "EmulationSpeed", speed);
}

+ (void)setRuntimeEmulationSpeedPercent:(int)percent
{
  IOSHost::SetFloatSettingRuntime("Main", "EmulationSpeed", std::max(percent, 10) / 100.0f);
}

+ (BOOL)isVMRunning
{
  return IOSHost::IsSystemActive() ? YES : NO;
}

+ (BOOL)hasBIOS
{
  return IOSHost::HasBIOS() ? YES : NO;
}

+ (void)requestVMBoot
{
  [self requestVMBootLoadingLastSaveState:YES];
}

+ (void)requestVMBootLoadingLastSaveState:(BOOL)loadLastSaveState
{
  DSAttachRenderView();
  const std::string path = IOSHost::GetStringSetting("GameISO", "BootISO", "");
  IOSHost::BootGameWithResume(path, loadLastSaveState);
}

@end

//////////////////////////////////////////////////////////////////////////
// BIOS
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSBIOS)

+ (nonnull NSString*)biosDirectory
{
  NSString* dir = DSString(IOSHost::GetBIOSDirectory());
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  return dir;
}

+ (nonnull NSArray<ARMSX2BIOSInfo*>*)availableBIOSInfos
{
  NSMutableArray* list = [NSMutableArray array];
  for (const IOSHost::BIOSInfo& b : IOSHost::ListBIOSImages())
  {
    ARMSX2BIOSInfo* info = [ARMSX2BIOSInfo new];
    info.fileName = DSString(b.file_name);
    info.filePath = DSString(b.path);
    info.regionName = DSString(b.region);
    info.countryCode = DSString(b.country_code);
    info.descriptionText = DSString(b.description);
    info.valid = b.valid;
    [list addObject:info];
  }
  return list;
}

+ (nonnull NSString*)defaultBIOSName
{
  return [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultBIOSKey] ?: @"";
}

+ (void)setDefaultBIOS:(nonnull NSString*)biosName
{
  // DuckStation picks the BIOS matching the disc region automatically; remember the choice for the UI.
  [[NSUserDefaults standardUserDefaults] setObject:biosName forKey:kDefaultBIOSKey];
}

@end

//////////////////////////////////////////////////////////////////////////
// Settings (shared INI with the core; PS2-only keys are stored but ignored)
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSSettings)

+ (int)getINIInt:(nonnull NSString*)section key:(nonnull NSString*)key defaultValue:(int)def
{
  return IOSHost::GetIntSetting(section.UTF8String, key.UTF8String, def);
}

+ (BOOL)getINIBool:(nonnull NSString*)section key:(nonnull NSString*)key defaultValue:(BOOL)def
{
  return IOSHost::GetBoolSetting(section.UTF8String, key.UTF8String, def) ? YES : NO;
}

+ (float)getINIFloat:(nonnull NSString*)section key:(nonnull NSString*)key defaultValue:(float)def
{
  return IOSHost::GetFloatSetting(section.UTF8String, key.UTF8String, def);
}

+ (nonnull NSString*)getINIString:(nonnull NSString*)section key:(nonnull NSString*)key defaultValue:(nonnull NSString*)def
{
  return DSString(IOSHost::GetStringSetting(section.UTF8String, key.UTF8String, def.UTF8String));
}

+ (void)setINIInt:(nonnull NSString*)section key:(nonnull NSString*)key value:(int)value
{
  IOSHost::SetIntSetting(section.UTF8String, key.UTF8String, value);
}

+ (void)setINIBool:(nonnull NSString*)section key:(nonnull NSString*)key value:(BOOL)value
{
  IOSHost::SetBoolSetting(section.UTF8String, key.UTF8String, value);
}

+ (void)setINIFloat:(nonnull NSString*)section key:(nonnull NSString*)key value:(float)value
{
  IOSHost::SetFloatSetting(section.UTF8String, key.UTF8String, value);
}

+ (void)setINIString:(nonnull NSString*)section key:(nonnull NSString*)key value:(nonnull NSString*)value
{
  IOSHost::SetStringSetting(section.UTF8String, key.UTF8String, value.UTF8String);
}

+ (void)clearINISection:(nonnull NSString*)section
{
  IOSHost::ClearSettingsSection(section.UTF8String);
}

+ (void)applyGraphicsSettingsNow
{
  IOSHost::CommitSettings();
}

+ (void)flushINISettings
{
  IOSHost::CommitSettings();
}

@end

//////////////////////////////////////////////////////////////////////////
// Save states
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSSaveStates)

+ (BOOL)hasValidSaveStateGame
{
  return !IOSHost::GetCurrentGameSerial().empty();
}

+ (nonnull NSArray<ARMSX2SaveStateSlotInfo*>*)saveStateSlots
{
  NSMutableArray* slots = [NSMutableArray array];
  const std::string serial = IOSHost::GetCurrentGameSerial();
  if (serial.empty())
    return slots;

  const NSInteger armsx2Slots[] = {-2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
  for (NSInteger slot : armsx2Slots)
  {
    const std::string path = IOSHost::GetSaveStatePathForSerial(serial, DSSlotFromARMSX2(slot));
    NSString* nsPath = DSString(path);
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:nsPath error:nil];

    ARMSX2SaveStateSlotInfo* info = [ARMSX2SaveStateSlotInfo new];
    info.slot = slot;
    info.occupied = attrs != nil;
    info.filePath = nsPath;
    info.fileName = nsPath.lastPathComponent ?: @"";
    info.modifiedDate = attrs.fileModificationDate;
    if (attrs)
    {
      std::vector<unsigned char> png = IOSHost::GetSaveStatePreviewPNG(path);
      if (!png.empty())
        info.previewPNGData = [NSData dataWithBytes:png.data() length:png.size()];
    }
    [slots addObject:info];
  }
  return slots;
}

+ (void)saveStateToSlot:(NSInteger)slot
             completion:(nullable void (^)(BOOL saved, NSString* _Nullable backupToken))completion
{
  const int ds_slot = DSSlotFromARMSX2(slot);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const bool ok = IOSHost::SaveStateToSlotSync(ds_slot);
    if (completion)
      dispatch_async(dispatch_get_main_queue(), ^{ completion(ok ? YES : NO, nil); });
  });
}

+ (void)logAutoSaveSkipped:(nonnull NSString*)reason
{
}

+ (void)autoSaveLeavingGame:(BOOL)leaving completion:(nullable ARMSX2SaveStateCompletion)completion
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const bool ok = IOSHost::SaveResumeState();
    if (completion)
      dispatch_async(dispatch_get_main_queue(), ^{ completion(ok ? YES : NO); });
  });
}

+ (void)loadStateFromSlot:(NSInteger)slot
         expectedModified:(nullable NSDate*)expectedModified
              keepingUndo:(BOOL)keepingUndo
               completion:(nullable void (^)(BOOL loaded, NSString* _Nullable undoPath))completion
{
  const int ds_slot = DSSlotFromARMSX2(slot);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString* undoPath = nil;
    if (keepingUndo)
    {
      NSString* tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"undo-%@.sav", NSUUID.UUID.UUIDString]];
      if (IOSHost::SaveStateToPathSync(DSStd(tmp)))
        undoPath = tmp;
    }
    const bool ok = IOSHost::LoadStateFromSlotSync(ds_slot);
    if (completion)
      dispatch_async(dispatch_get_main_queue(), ^{ completion(ok ? YES : NO, ok ? undoPath : nil); });
  });
}

+ (void)undoLoadStateFromPath:(nonnull NSString*)path completion:(nullable ARMSX2SaveStateCompletion)completion
{
  const std::string p = DSStd(path);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const bool ok = IOSHost::LoadStateFromPathSync(p);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (completion)
      dispatch_async(dispatch_get_main_queue(), ^{ completion(ok ? YES : NO); });
  });
}

+ (void)discardUndoLoadStateAtPath:(nonnull NSString*)path
{
  [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

static NSString* DSDeletedPath(NSString* path)
{
  return [path stringByAppendingString:@".deleted"];
}

+ (void)deleteSaveStateInSlot:(NSInteger)slot completion:(nullable ARMSX2SaveStateCompletion)completion
{
  NSString* path = DSString(IOSHost::GetSaveStatePathForSlot(DSSlotFromARMSX2(slot)));
  NSFileManager* fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:DSDeletedPath(path) error:nil];
  const BOOL ok = path.length > 0 && [fm moveItemAtPath:path toPath:DSDeletedPath(path) error:nil];
  if (completion)
    dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
}

+ (void)restoreDeletedSaveStateInSlot:(NSInteger)slot completion:(nullable ARMSX2SaveStateCompletion)completion
{
  NSString* path = DSString(IOSHost::GetSaveStatePathForSlot(DSSlotFromARMSX2(slot)));
  const BOOL ok = path.length > 0 && [[NSFileManager defaultManager] moveItemAtPath:DSDeletedPath(path)
                                                                              toPath:path
                                                                               error:nil];
  if (completion)
    dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
}

+ (void)finishDeletingSaveStateInSlot:(NSInteger)slot
{
  NSString* path = DSString(IOSHost::GetSaveStatePathForSlot(DSSlotFromARMSX2(slot)));
  if (path.length > 0)
    [[NSFileManager defaultManager] removeItemAtPath:DSDeletedPath(path) error:nil];
}

+ (void)undoSaveOverInSlot:(NSInteger)slot
               backupToken:(nonnull NSString*)backupToken
                completion:(nullable ARMSX2SaveStateCompletion)completion
{
  if (completion)
    dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
}

+ (double)currentGamePlayedSeconds
{
  return 0;
}

@end

//////////////////////////////////////////////////////////////////////////
// Audio
//////////////////////////////////////////////////////////////////////////

@implementation ARMSX2Bridge (DSAudio)

+ (int)emulatorVolumePercent
{
  return IOSHost::GetIntSetting("Audio", "OutputVolume", 100);
}

+ (void)setEmulatorVolumePercent:(int)value
{
  IOSHost::SetIntSetting("Audio", "OutputVolume", value);
  IOSHost::SetIntSetting("Audio", "FastForwardVolume", value);
  IOSHost::CommitSettings();
}

@end

//////////////////////////////////////////////////////////////////////////
// Menu <-> emulator notifications (what ARMSX2's SceneDelegate did)
//////////////////////////////////////////////////////////////////////////

void DSBridgeHandleHostEvent(int event)
{
  switch (static_cast<IOSHost::Event>(event))
  {
    case IOSHost::Event::Stopped:
      DSPost(@"ARMSX2iOSVMDidShutdown");
      break;
    default:
      break;
  }
}
