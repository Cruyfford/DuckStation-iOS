// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

#import "DSCheats.h"

#include "../../ios_host.h"

#include "core/cheats.h"
#include "core/host.h"
#include "core/settings.h"
#include "core/system.h"

#include <functional>
#include <memory>
#include <string>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

@interface DSCheatEntry ()
@property(nonatomic, readwrite) NSInteger index;
@property(nonatomic, copy, readwrite) NSString* name;
@property(nonatomic, copy, readwrite) NSString* group;
@property(nonatomic, copy, readwrite) NSString* code;
@property(nonatomic, readwrite) BOOL enabled;
@property(nonatomic, readwrite) BOOL manual;
@end

@implementation DSCheatEntry
@end

static NSString* DSString(const std::string& s)
{
  NSString* str = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
  return str ? str : @"";
}

// Runs on the emulator thread and waits for it.
template<typename F>
static void DSRunOnCPU(F&& fn)
{
  Host::RunOnCPUThread(std::function<void()>(std::forward<F>(fn)), true);
}

// Cheats must be enabled in the settings for the core to apply them each frame.
static void DSEnsureCheatsEnabled()
{
  if (g_settings.enable_cheats)
    return;
  IOSHost::SetBoolSetting("Console", "EnableCheats", true);
  g_settings.enable_cheats = true;
}

static CheatList* DSGetOrCreateList()
{
  if (!System::HasCheatList())
  {
    if (!System::LoadCheatList())
      System::SetCheatList(std::make_unique<CheatList>());
  }
  return System::GetCheatList();
}

static NSArray<DSCheatEntry*>* DSSnapshot()
{
  NSMutableArray<DSCheatEntry*>* out = [NSMutableArray array];
  CheatList* cl = System::HasCheatList() ? System::GetCheatList() : nullptr;
  if (!cl)
    return out;
  for (u32 i = 0; i < cl->GetCodeCount(); i++)
  {
    const CheatCode& cc = cl->GetCode(i);
    DSCheatEntry* e = [DSCheatEntry new];
    e.index = i;
    e.name = DSString(cc.description);
    e.group = DSString(cc.group);
    e.code = DSString(cc.GetInstructionsAsString());
    e.enabled = cc.enabled;
    e.manual = cc.IsManuallyActivated();
    [out addObject:e];
  }
  return out;
}

@implementation DSCheats

+ (BOOL)isGameRunning
{
  return IOSHost::IsSystemActive();
}

+ (NSString*)currentGameTitle
{
  return DSString(IOSHost::GetCurrentGameTitle());
}

+ (NSArray<DSCheatEntry*>*)loadCheats
{
  NSArray<DSCheatEntry*>* result = @[];
  bool changed_setting = false;
  DSRunOnCPU([&]() {
    if (!System::IsValid())
      return;
    changed_setting = !g_settings.enable_cheats;
    DSEnsureCheatsEnabled();
    DSGetOrCreateList();
    result = DSSnapshot();
  });
  if (changed_setting)
    IOSHost::CommitSettings();
  return result;
}

+ (NSInteger)loadFromDatabase
{
  NSInteger count = 0;
  DSRunOnCPU([&]() {
    if (!System::IsValid())
      return;
    DSEnsureCheatsEnabled();
    if (System::LoadCheatListFromDatabase())
    {
      count = System::GetCheatList()->GetCodeCount();
      System::SaveCheatList();
    }
  });
  return count;
}

+ (BOOL)addCheatNamed:(NSString*)name group:(NSString*)group code:(NSString*)code
{
  BOOL ok = NO;
  const std::string sname = name.length ? std::string(name.UTF8String) : std::string("Cheat");
  const std::string sgroup = group.length ? std::string(group.UTF8String) : std::string();
  const std::string scode = code.UTF8String ? std::string(code.UTF8String) : std::string();
  DSRunOnCPU([&]() {
    if (!System::IsValid())
      return;
    CheatCode cc;
    cc.description = sname;
    cc.group = sgroup;
    cc.type = CheatCode::Type::Gameshark;
    cc.activation = CheatCode::Activation::EndFrame;
    if (!cc.SetInstructionsFromString(scode) || !cc.Valid())
      return;
    cc.enabled = true;
    DSEnsureCheatsEnabled();
    DSGetOrCreateList()->AddCode(std::move(cc));
    System::SaveCheatList();
    ok = YES;
  });
  return ok;
}

+ (NSInteger)importCheatFile:(NSString*)path
{
  NSInteger added = -1;
  const std::string spath = path.fileSystemRepresentation;
  DSRunOnCPU([&]() {
    if (!System::IsValid())
      return;
    CheatList imported;
    if (!imported.LoadFromFile(spath.c_str(), CheatList::Format::Autodetect))
      return;
    DSEnsureCheatsEnabled();
    DSGetOrCreateList()->MergeList(imported);
    System::SaveCheatList();
    added = imported.GetCodeCount();
  });
  return added;
}

+ (void)setCheatAtIndex:(NSInteger)index enabled:(BOOL)enabled
{
  DSRunOnCPU([&]() {
    if (!System::IsValid() || !System::HasCheatList())
      return;
    System::SetCheatCodeState(static_cast<u32>(index), enabled);
    System::SaveCheatList();
  });
}

+ (void)applyCheatAtIndex:(NSInteger)index
{
  DSRunOnCPU([&]() {
    if (System::IsValid() && System::HasCheatList())
      System::ApplyCheatCode(static_cast<u32>(index));
  });
}

+ (void)removeCheatAtIndex:(NSInteger)index
{
  DSRunOnCPU([&]() {
    if (!System::IsValid() || !System::HasCheatList())
      return;
    CheatList* cl = System::GetCheatList();
    if (index < 0 || static_cast<u32>(index) >= cl->GetCodeCount())
      return;
    cl->RemoveCode(static_cast<u32>(index));
    System::SaveCheatList();
  });
}

+ (void)removeAllCheats
{
  DSRunOnCPU([&]() {
    if (System::IsValid())
      System::ClearCheatList(true);
  });
}

@end
