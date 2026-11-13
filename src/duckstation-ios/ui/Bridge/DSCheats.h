// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// PS1 cheat codes (GameShark / PCSXR / libretro / ePSXe formats) for the running game.
// All methods block until the emulator thread has handled them; call them off the main thread.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSCheatEntry : NSObject
@property(nonatomic, readonly) NSInteger index;
@property(nonatomic, copy, readonly) NSString* name;
@property(nonatomic, copy, readonly) NSString* group;
@property(nonatomic, copy, readonly) NSString* code;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL manual;
@end

@interface DSCheats : NSObject

/// YES while a game is running (cheats only apply to the running game).
+ (BOOL)isGameRunning NS_SWIFT_NAME(isGameRunning());

/// Title of the running game, used for the cheat file name.
+ (NSString*)currentGameTitle NS_SWIFT_NAME(currentGameTitle());

/// Turns cheats on in the settings and loads the game's saved list. Returns the current codes.
+ (NSArray<DSCheatEntry*>*)loadCheats NS_SWIFT_NAME(loadCheats());

/// Replaces the list with the built-in database codes for this game. Returns the number found.
+ (NSInteger)loadFromDatabase NS_SWIFT_NAME(loadFromDatabase());

/// Adds a code typed by the user (e.g. "8009C6E4 0FFF", one per line). Returns NO if it doesn't parse.
+ (BOOL)addCheatNamed:(NSString*)name group:(NSString*)group code:(NSString*)code NS_SWIFT_NAME(addCheatNamed(_:group:code:));

/// Merges codes from a .cht / .txt cheat file. Returns the number added, or -1 on failure.
+ (NSInteger)importCheatFile:(NSString*)path NS_SWIFT_NAME(importCheatFile(_:));

+ (void)setCheatAtIndex:(NSInteger)index enabled:(BOOL)enabled NS_SWIFT_NAME(setCheatAt(_:enabled:));
+ (void)applyCheatAtIndex:(NSInteger)index NS_SWIFT_NAME(applyCheat(at:));
+ (void)removeCheatAtIndex:(NSInteger)index NS_SWIFT_NAME(removeCheat(at:));
+ (void)removeAllCheats NS_SWIFT_NAME(removeAllCheats());

@end

NS_ASSUME_NONNULL_END
