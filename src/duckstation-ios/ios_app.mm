// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// UIKit frontend for DuckStation on iOS: game library, emulator screen with touch controls, settings.
// Compiled with ARC.

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "ios_host.h"

#include <cmath>
#include <cstring>
#include <iterator>
#include <set>
#include <string>
#include <vector>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

static NSString* const kHostEventNotification = @"DSHostEvent";
static NSString* const kLanguageKey = @"DSLanguage";

//////////////////////////////////////////////////////////////////////////
// Localization (English default, Arabic option)
//////////////////////////////////////////////////////////////////////////

static BOOL IsArabic()
{
  return [[[NSUserDefaults standardUserDefaults] stringForKey:kLanguageKey] isEqualToString:@"ar"];
}

static NSString* L(NSString* key)
{
  static NSDictionary<NSString*, NSArray<NSString*>*>* table = @{
    // key : @[English, Arabic]
    @"library" : @[ @"Games", @"الألعاب" ],
    @"settings" : @[ @"Settings", @"الإعدادات" ],
    @"import" : @[ @"Import", @"استيراد" ],
    @"import_what" : @[ @"What are you importing?", @"ماذا تريد أن تستورد؟" ],
    @"import_games" : @[ @"Games", @"ألعاب" ],
    @"import_bios" : @[ @"BIOS", @"بايوس" ],
    @"cancel" : @[ @"Cancel", @"إلغاء" ],
    @"ok" : @[ @"OK", @"حسناً" ],
    @"empty" : @[ @"No games yet.\n\nTap Import, or copy games into\nFiles › On My iPhone › DuckStation › Games",
                  @"لا توجد ألعاب بعد.\n\nاضغط استيراد، أو انسخ الألعاب إلى\nالملفات › على الـiPhone › DuckStation › Games" ],
    @"no_bios_title" : @[ @"BIOS required", @"البايوس مطلوب" ],
    @"no_bios_msg" : @[ @"Import a PlayStation BIOS (e.g. SCPH1001.BIN) using Import › BIOS.",
                        @"استورد ملف بايوس بلايستيشن (مثل SCPH1001.BIN) من استيراد › بايوس." ],
    @"error" : @[ @"Error", @"خطأ" ],
    @"menu" : @[ @"Menu", @"القائمة" ],
    @"resume" : @[ @"Resume", @"متابعة" ],
    @"save_state" : @[ @"Save State", @"حفظ الحالة" ],
    @"load_state" : @[ @"Load State", @"تحميل الحالة" ],
    @"slot" : @[ @"Slot %d", @"الخانة %d" ],
    @"reset" : @[ @"Reset", @"إعادة تشغيل" ],
    @"quit" : @[ @"Quit Game", @"الخروج من اللعبة" ],
    @"language" : @[ @"Language", @"اللغة" ],
    @"video" : @[ @"Video", @"الصورة" ],
    @"resolution" : @[ @"Internal Resolution", @"الدقة الداخلية" ],
    @"show_fps" : @[ @"Show FPS", @"إظهار عدد الإطارات" ],
    @"widescreen" : @[ @"Widescreen Hack", @"شاشة عريضة" ],
    @"pgxp" : @[ @"PGXP (Geometry Correction)", @"PGXP (تصحيح الأشكال)" ],
    @"system" : @[ @"System", @"النظام" ],
    @"fast_boot" : @[ @"Fast Boot (skip BIOS intro)", @"إقلاع سريع (تخطي شعار البايوس)" ],
    @"bios" : @[ @"BIOS", @"البايوس" ],
    @"bios_found" : @[ @"BIOS found", @"تم العثور على البايوس" ],
    @"bios_missing" : @[ @"BIOS not found", @"لم يتم العثور على البايوس" ],
    @"about" : @[ @"About", @"حول" ],
    @"about_text" : @[ @"DuckStation for iOS — private build (GPL-3.0 base)",
                       @"داك ستيشن لـ iOS — نسخة خاصة (أساس GPL-3.0)" ],
    @"imported" : @[ @"Imported %d file(s).", @"تم استيراد %d ملف." ],
  };

  NSArray<NSString*>* entry = table[key];
  if (!entry)
    return key;
  return IsArabic() ? entry[1] : entry[0];
}

static void ApplyLanguageDirection()
{
  const UISemanticContentAttribute attr =
    IsArabic() ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
  [[UIView appearance] setSemanticContentAttribute:attr];
  [[UINavigationBar appearance] setSemanticContentAttribute:attr];
}

static void ShowAlert(UIViewController* vc, NSString* title, NSString* message, void (^done)(void))
{
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:L(@"ok")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) {
                                            if (done)
                                              done();
                                          }]];
  [vc presentViewController:alert animated:YES completion:nil];
}

static void HostEventCallback(IOSHost::Event event, const char* message)
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName:kHostEventNotification
                  object:nil
                userInfo:@{@"event" : @(static_cast<int>(event)), @"message" : @(message ? message : "")}];
}

//////////////////////////////////////////////////////////////////////////
// Render view: hosts the CAMetalLayer created by the core.
//////////////////////////////////////////////////////////////////////////

@interface DSRenderView : UIView
@end

@implementation DSRenderView
{
  CGSize _lastPixelSize;
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

  const CGFloat scale = self.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
  const CGSize px = CGSizeMake(std::floor(self.bounds.size.width * scale), std::floor(self.bounds.size.height * scale));
  if (!CGSizeEqualToSize(px, _lastPixelSize) && px.width > 0 && px.height > 0)
  {
    const BOOL first = CGSizeEqualToSize(_lastPixelSize, CGSizeZero);
    _lastPixelSize = px;
    if (!first)
      IOSHost::ResizeRenderView(static_cast<int>(px.width), static_cast<int>(px.height), static_cast<float>(scale));
  }
}

- (CGSize)pixelSize
{
  const CGFloat scale = self.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
  return CGSizeMake(std::floor(self.bounds.size.width * scale), std::floor(self.bounds.size.height * scale));
}

@end

//////////////////////////////////////////////////////////////////////////
// Touch controller overlay
//////////////////////////////////////////////////////////////////////////

struct OverlayButton
{
  IOSHost::PadButton button;
  CGPoint center;
  CGFloat radius;
  const char* label;
  bool pill; // shoulder/start/select are drawn as rounded rectangles
};

@interface DSControllerOverlay : UIView
@property(nonatomic, copy) void (^onMenu)(void);
@end

@implementation DSControllerOverlay
{
  std::vector<OverlayButton> _buttons;
  CGPoint _dpadCenter;
  CGFloat _dpadRadius;
  CGRect _menuRect;
  std::set<int> _pressed;
  UIImpactFeedbackGenerator* _haptic;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    self.multipleTouchEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
  }
  return self;
}

// gameRect: where the picture is, so portrait controls go below it.
- (void)layoutForGameRect:(CGRect)gameRect
{
  const CGRect b = self.bounds;
  const UIEdgeInsets safe = self.safeAreaInsets;
  const BOOL landscape = b.size.width > b.size.height;
  _buttons.clear();

  CGFloat dpadY, faceY, shoulderY, startY;
  CGFloat leftX, rightX;
  if (landscape)
  {
    _dpadRadius = std::min(b.size.height * 0.17, 95.0);
    leftX = safe.left + _dpadRadius * 1.35;
    rightX = b.size.width - safe.right - _dpadRadius * 1.35;
    dpadY = faceY = b.size.height * 0.62;
    shoulderY = safe.top + 34;
    startY = b.size.height - safe.bottom - 26;
  }
  else
  {
    const CGFloat top = CGRectGetMaxY(gameRect);
    const CGFloat h = b.size.height - safe.bottom - top;
    _dpadRadius = std::min(std::min(b.size.width * 0.19, h * 0.24), 95.0);
    leftX = b.size.width * 0.25;
    rightX = b.size.width * 0.75;
    shoulderY = top + 36;
    dpadY = faceY = top + h * 0.50;
    startY = b.size.height - safe.bottom - 30;
  }

  _dpadCenter = CGPointMake(leftX, dpadY);

  const CGFloat fr = _dpadRadius * 0.40; // face button radius
  const CGFloat off = _dpadRadius * 0.66;
  _buttons.push_back({IOSHost::PadButton::Triangle, CGPointMake(rightX, faceY - off), fr, "△", false});
  _buttons.push_back({IOSHost::PadButton::Cross, CGPointMake(rightX, faceY + off), fr, "✕", false});
  _buttons.push_back({IOSHost::PadButton::Square, CGPointMake(rightX - off, faceY), fr, "□", false});
  _buttons.push_back({IOSHost::PadButton::Circle, CGPointMake(rightX + off, faceY), fr, "○", false});

  const CGFloat sr = 26; // shoulder half-height-ish
  const CGFloat sx = landscape ? (safe.left + 60) : 56;
  const CGFloat ex = b.size.width - (landscape ? (safe.right + 60) : 56);
  _buttons.push_back({IOSHost::PadButton::L2, CGPointMake(sx, shoulderY), sr, "L2", true});
  _buttons.push_back({IOSHost::PadButton::L1, CGPointMake(sx + 2.6 * sr + 8, shoulderY), sr, "L1", true});
  _buttons.push_back({IOSHost::PadButton::R1, CGPointMake(ex - 2.6 * sr - 8, shoulderY), sr, "R1", true});
  _buttons.push_back({IOSHost::PadButton::R2, CGPointMake(ex, shoulderY), sr, "R2", true});

  const CGFloat mx = b.size.width * 0.5;
  _buttons.push_back({IOSHost::PadButton::Select, CGPointMake(mx - 62, startY), 20, "SELECT", true});
  _buttons.push_back({IOSHost::PadButton::Start, CGPointMake(mx + 62, startY), 20, "START", true});

  _menuRect = landscape ? CGRectMake(mx - 34, safe.top + 8, 68, 30) : CGRectMake(mx - 34, startY - 62, 68, 30);

  [self setNeedsDisplay];
}

- (CGRect)rectForButton:(const OverlayButton&)btn
{
  if (btn.pill)
  {
    const CGFloat w = btn.radius * (strlen(btn.label) > 2 ? 3.4 : 2.6);
    const CGFloat h = btn.radius * 1.4;
    return CGRectMake(btn.center.x - w / 2, btn.center.y - h / 2, w, h);
  }
  return CGRectMake(btn.center.x - btn.radius, btn.center.y - btn.radius, btn.radius * 2, btn.radius * 2);
}

- (void)drawRect:(CGRect)rect
{
  UIColor* fill = [UIColor colorWithWhite:1.0 alpha:0.16];
  UIColor* fillOn = [UIColor colorWithWhite:1.0 alpha:0.45];
  UIColor* stroke = [UIColor colorWithWhite:1.0 alpha:0.45];

  // D-pad
  const CGFloat arm = _dpadRadius * 0.36;
  const CGFloat len = _dpadRadius;
  struct Arm
  {
    IOSHost::PadButton b;
    CGRect r;
  } arms[] = {
    {IOSHost::PadButton::Up, CGRectMake(_dpadCenter.x - arm, _dpadCenter.y - len, arm * 2, len - arm)},
    {IOSHost::PadButton::Down, CGRectMake(_dpadCenter.x - arm, _dpadCenter.y + arm, arm * 2, len - arm)},
    {IOSHost::PadButton::Left, CGRectMake(_dpadCenter.x - len, _dpadCenter.y - arm, len - arm, arm * 2)},
    {IOSHost::PadButton::Right, CGRectMake(_dpadCenter.x + arm, _dpadCenter.y - arm, len - arm, arm * 2)},
  };
  UIBezierPath* centerPath =
    [UIBezierPath bezierPathWithRect:CGRectMake(_dpadCenter.x - arm, _dpadCenter.y - arm, arm * 2, arm * 2)];
  [fill setFill];
  [centerPath fill];
  for (const Arm& a : arms)
  {
    UIBezierPath* p = [UIBezierPath bezierPathWithRoundedRect:a.r cornerRadius:6];
    [(_pressed.count(static_cast<int>(a.b)) ? fillOn : fill) setFill];
    [p fill];
    [stroke setStroke];
    p.lineWidth = 1.5;
    [p stroke];
  }

  // Buttons
  for (const OverlayButton& btn : _buttons)
  {
    const CGRect r = [self rectForButton:btn];
    UIBezierPath* p = btn.pill ? [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:r.size.height / 2] :
                                 [UIBezierPath bezierPathWithOvalInRect:r];
    [(_pressed.count(static_cast<int>(btn.button)) ? fillOn : fill) setFill];
    [p fill];
    [stroke setStroke];
    p.lineWidth = 1.5;
    [p stroke];

    NSString* text = [NSString stringWithUTF8String:btn.label];
    const CGFloat fontSize = btn.pill ? (strlen(btn.label) > 2 ? 11 : 14) : btn.radius * 0.9;
    NSDictionary* attrs = @{
      NSFontAttributeName : [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold],
      NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.85]
    };
    const CGSize ts = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake(CGRectGetMidX(r) - ts.width / 2, CGRectGetMidY(r) - ts.height / 2)
       withAttributes:attrs];
  }

  // Menu
  UIBezierPath* mp = [UIBezierPath bezierPathWithRoundedRect:_menuRect cornerRadius:_menuRect.size.height / 2];
  [fill setFill];
  [mp fill];
  NSDictionary* mattrs = @{
    NSFontAttributeName : [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
    NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.85]
  };
  NSString* menu = L(@"menu");
  const CGSize ms = [menu sizeWithAttributes:mattrs];
  [menu drawAtPoint:CGPointMake(CGRectGetMidX(_menuRect) - ms.width / 2, CGRectGetMidY(_menuRect) - ms.height / 2)
     withAttributes:mattrs];
}

- (void)collectPressed:(std::set<int>&)out forPoint:(CGPoint)pt
{
  // D-pad: 8-way by angle with overlapping sectors for diagonals.
  const CGFloat dx = pt.x - _dpadCenter.x;
  const CGFloat dy = pt.y - _dpadCenter.y;
  const CGFloat dist = std::sqrt(dx * dx + dy * dy);
  if (dist <= _dpadRadius * 1.35 && dist >= _dpadRadius * 0.15)
  {
    double angle = std::atan2(dy, dx) * 180.0 / M_PI; // 0 = right, 90 = down
    if (angle < 0)
      angle += 360.0;
    if (angle <= 67.5 || angle >= 292.5)
      out.insert(static_cast<int>(IOSHost::PadButton::Right));
    if (angle >= 22.5 && angle <= 157.5)
      out.insert(static_cast<int>(IOSHost::PadButton::Down));
    if (angle >= 112.5 && angle <= 247.5)
      out.insert(static_cast<int>(IOSHost::PadButton::Left));
    if (angle >= 202.5 && angle <= 337.5)
      out.insert(static_cast<int>(IOSHost::PadButton::Up));
    return;
  }

  // Buttons: nearest within a generous radius.
  const OverlayButton* best = nullptr;
  CGFloat best_dist = CGFLOAT_MAX;
  for (const OverlayButton& btn : _buttons)
  {
    const CGRect r = CGRectInset([self rectForButton:btn], -12, -12);
    if (!CGRectContainsPoint(r, pt))
      continue;
    const CGFloat bx = pt.x - btn.center.x, by = pt.y - btn.center.y;
    const CGFloat d = bx * bx + by * by;
    if (d < best_dist)
    {
      best_dist = d;
      best = &btn;
    }
  }
  if (best)
    out.insert(static_cast<int>(best->button));
}

- (void)updateTouches:(UIEvent*)event
{
  std::set<int> now;
  for (UITouch* t in event.allTouches)
  {
    if (t.view != self || t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled)
      continue;
    [self collectPressed:now forPoint:[t locationInView:self]];
  }

  bool changed = false;
  for (int b : _pressed)
  {
    if (!now.count(b))
    {
      IOSHost::SetPadButton(static_cast<IOSHost::PadButton>(b), false);
      changed = true;
    }
  }
  for (int b : now)
  {
    if (!_pressed.count(b))
    {
      IOSHost::SetPadButton(static_cast<IOSHost::PadButton>(b), true);
      [_haptic impactOccurred];
      changed = true;
    }
  }
  _pressed = std::move(now);
  if (changed)
    [self setNeedsDisplay];
}

- (void)releaseAll
{
  for (int b : _pressed)
    IOSHost::SetPadButton(static_cast<IOSHost::PadButton>(b), false);
  _pressed.clear();
  [self setNeedsDisplay];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* t in touches)
  {
    if (CGRectContainsPoint(CGRectInset(_menuRect, -10, -10), [t locationInView:self]))
    {
      [self releaseAll];
      if (self.onMenu)
        self.onMenu();
      return;
    }
  }
  [self updateTouches:event];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self updateTouches:event];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self updateTouches:event];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self releaseAll];
}

@end

//////////////////////////////////////////////////////////////////////////
// Emulator screen
//////////////////////////////////////////////////////////////////////////

@interface DSEmulatorViewController : UIViewController
- (instancetype)initWithGamePath:(NSString*)path;
@end

@implementation DSEmulatorViewController
{
  NSString* _path;
  DSRenderView* _renderView;
  DSControllerOverlay* _overlay;
  BOOL _booted;
  BOOL _menuOpen;
  BOOL _closing;
}

- (instancetype)initWithGamePath:(NSString*)path
{
  if ((self = [super initWithNibName:nil bundle:nil]))
  {
    _path = [path copy];
    self.modalPresentationStyle = UIModalPresentationFullScreen;
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;

  _renderView = [[DSRenderView alloc] initWithFrame:self.view.bounds];
  _renderView.backgroundColor = UIColor.blackColor;
  _renderView.userInteractionEnabled = NO;
  [self.view addSubview:_renderView];

  _overlay = [[DSControllerOverlay alloc] initWithFrame:self.view.bounds];
  __weak DSEmulatorViewController* weakSelf = self;
  _overlay.onMenu = ^{
    [weakSelf showMenu];
  };
  [self.view addSubview:_overlay];

  NSNotificationCenter* nc = NSNotificationCenter.defaultCenter;
  [nc addObserver:self selector:@selector(hostEvent:) name:kHostEventNotification object:nil];
  [nc addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
  [nc addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
  [nc addObserver:self selector:@selector(controllersChanged) name:GCControllerDidConnectNotification object:nil];
  [nc addObserver:self selector:@selector(controllersChanged) name:GCControllerDidDisconnectNotification object:nil];
  [self controllersChanged];
}

- (void)dealloc
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
  return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
  return UIRectEdgeAll;
}

- (CGRect)gameRect
{
  const CGRect b = self.view.bounds;
  if (b.size.width > b.size.height)
    return b; // landscape: full screen, the core letterboxes to 4:3

  const CGFloat top = self.view.safeAreaInsets.top;
  return CGRectMake(0, top, b.size.width, std::floor(b.size.width * 3.0 / 4.0));
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  _renderView.frame = [self gameRect];
  _overlay.frame = self.view.bounds;
  [_overlay layoutForGameRect:_renderView.frame];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  if (_booted)
    return;

  _booted = YES;
  [self.view layoutIfNeeded];
  const CGSize px = [_renderView pixelSize];
  const CGFloat scale = self.view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
  IOSHost::SetRenderView((__bridge void*)_renderView, static_cast<int>(px.width), static_cast<int>(px.height),
                         static_cast<float>(scale));
  IOSHost::BootGame(std::string(_path.fileSystemRepresentation));
}

- (void)controllersChanged
{
  _overlay.hidden = GCController.controllers.count > 0;
}

- (void)appWillResignActive
{
  if (_booted && !_closing)
    IOSHost::SetPaused(true);
}

- (void)appDidBecomeActive
{
  if (_booted && !_closing && !_menuOpen)
    IOSHost::SetPaused(false);
}

- (void)hostEvent:(NSNotification*)note
{
  const auto event = static_cast<IOSHost::Event>([note.userInfo[@"event"] intValue]);
  NSString* message = note.userInfo[@"message"];
  switch (event)
  {
    case IOSHost::Event::Stopped:
      [self close];
      break;

    case IOSHost::Event::Error:
      ShowAlert(self, L(@"error"), message, ^{
        if (!IOSHost::IsSystemActive())
          [self close];
      });
      break;

    default:
      break;
  }
}

- (void)close
{
  if (_closing)
    return;
  _closing = YES;
  IOSHost::ClearRenderView();
  [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMenu
{
  if (_menuOpen)
    return;
  _menuOpen = YES;
  IOSHost::SetPaused(true);

  UIAlertController* sheet = [UIAlertController alertControllerWithTitle:_path.lastPathComponent.stringByDeletingPathExtension
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
  __weak DSEmulatorViewController* weakSelf = self;
  void (^done)(BOOL) = ^(BOOL resume) {
    DSEmulatorViewController* s = weakSelf;
    if (!s)
      return;
    s->_menuOpen = NO;
    if (resume)
      IOSHost::SetPaused(false);
  };

  [sheet addAction:[UIAlertAction actionWithTitle:L(@"resume")
                                            style:UIAlertActionStyleCancel
                                          handler:^(UIAlertAction*) { done(YES); }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"save_state")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) { [weakSelf showSlotPicker:YES done:done]; }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"load_state")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) { [weakSelf showSlotPicker:NO done:done]; }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"reset")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) {
                                            IOSHost::Reset();
                                            done(YES);
                                          }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"quit")
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction*) {
                                            done(NO);
                                            IOSHost::Shutdown(true);
                                          }]];
  [self presentSheet:sheet];
}

- (void)showSlotPicker:(BOOL)save done:(void (^)(BOOL))done
{
  UIAlertController* sheet = [UIAlertController alertControllerWithTitle:save ? L(@"save_state") : L(@"load_state")
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
  for (int slot = 1; slot <= 5; slot++)
  {
    NSString* title = [NSString stringWithFormat:L(@"slot"), slot];
    if (!save && !IOSHost::HasSaveStateInSlot(slot))
      continue;
    [sheet addAction:[UIAlertAction actionWithTitle:title
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction*) {
                                              if (save)
                                                IOSHost::SaveStateToSlot(slot);
                                              else
                                                IOSHost::LoadStateFromSlot(slot);
                                              done(YES);
                                            }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"cancel")
                                            style:UIAlertActionStyleCancel
                                          handler:^(UIAlertAction*) { done(YES); }]];
  [self presentSheet:sheet];
}

- (void)presentSheet:(UIAlertController*)sheet
{
  // iPad needs an anchor for action sheets.
  sheet.popoverPresentationController.sourceView = self.view;
  sheet.popoverPresentationController.sourceRect =
    CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
  [self presentViewController:sheet animated:YES completion:nil];
}

@end

//////////////////////////////////////////////////////////////////////////
// Settings
//////////////////////////////////////////////////////////////////////////

struct ToggleSetting
{
  const char* label_key;
  const char* section;
  const char* key;
  bool default_value;
};

static const ToggleSetting kVideoToggles[] = {
  {"show_fps", "Display", "ShowFPS", false},
  {"widescreen", "GPU", "WidescreenHack", false},
  {"pgxp", "GPU", "PGXPEnable", false},
};

static const ToggleSetting kSystemToggles[] = {
  {"fast_boot", "BIOS", "PatchFastBoot", false},
};

enum SettingsSection
{
  SectionLanguage,
  SectionVideo,
  SectionSystem,
  SectionBIOS,
  SectionAbout,
  SectionCount
};

@interface DSSettingsViewController : UITableViewController
@property(nonatomic, copy) void (^onLanguageChanged)(void);
@end

@implementation DSSettingsViewController

- (instancetype)init
{
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.title = L(@"settings");
  self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                  target:self
                                                  action:@selector(closeSettings)];
}

- (void)closeSettings
{
  IOSHost::CommitSettings();
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
  return SectionCount;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
  switch (section)
  {
    case SectionLanguage:
      return L(@"language");
    case SectionVideo:
      return L(@"video");
    case SectionSystem:
      return L(@"system");
    case SectionBIOS:
      return L(@"bios");
    default:
      return L(@"about");
  }
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section
{
  if (section == SectionBIOS)
    return @"Files › On My iPhone › DuckStation › BIOS";
  return nil;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
  switch (section)
  {
    case SectionLanguage:
      return 2;
    case SectionVideo:
      return 1 + static_cast<NSInteger>(std::size(kVideoToggles));
    case SectionSystem:
      return static_cast<NSInteger>(std::size(kSystemToggles));
    default:
      return 1;
  }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
  UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
  const ToggleSetting* toggle = nullptr;

  switch (indexPath.section)
  {
    case SectionLanguage:
    {
      const BOOL arabicRow = (indexPath.row == 1);
      cell.textLabel.text = arabicRow ? @"العربية" : @"English";
      cell.accessoryType = (arabicRow == IsArabic()) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
      return cell;
    }

    case SectionVideo:
      if (indexPath.row == 0)
      {
        cell.textLabel.text = L(@"resolution");
        cell.detailTextLabel.text =
          [NSString stringWithFormat:@"%dx", IOSHost::GetIntSetting("GPU", "ResolutionScale", 1)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
      }
      toggle = &kVideoToggles[indexPath.row - 1];
      break;

    case SectionSystem:
      toggle = &kSystemToggles[indexPath.row];
      break;

    case SectionBIOS:
      cell.textLabel.text = IOSHost::HasBIOS() ? L(@"bios_found") : L(@"bios_missing");
      cell.textLabel.textColor = IOSHost::HasBIOS() ? UIColor.systemGreenColor : UIColor.systemRedColor;
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      return cell;

    default:
      cell.textLabel.text = L(@"about_text");
      cell.textLabel.numberOfLines = 0;
      cell.selectionStyle = UITableViewCellSelectionStyleNone;
      return cell;
  }

  cell.textLabel.text = L(@(toggle->label_key));
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch* sw = [[UISwitch alloc] init];
  sw.on = IOSHost::GetBoolSetting(toggle->section, toggle->key, toggle->default_value);
  sw.tag = (indexPath.section << 8) | indexPath.row;
  [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = sw;
  return cell;
}

- (void)toggleChanged:(UISwitch*)sw
{
  const NSInteger section = sw.tag >> 8;
  const NSInteger row = sw.tag & 0xFF;
  const ToggleSetting& t = (section == SectionVideo) ? kVideoToggles[row - 1] : kSystemToggles[row];
  IOSHost::SetBoolSetting(t.section, t.key, sw.on);
  IOSHost::CommitSettings();
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  if (indexPath.section == SectionLanguage)
  {
    [[NSUserDefaults standardUserDefaults] setObject:(indexPath.row == 1) ? @"ar" : @"en" forKey:kLanguageKey];
    ApplyLanguageDirection();
    void (^changed)(void) = self.onLanguageChanged;
    [self dismissViewControllerAnimated:YES completion:^{
      if (changed)
        changed();
    }];
    return;
  }

  if (indexPath.section == SectionVideo && indexPath.row == 0)
  {
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:L(@"resolution")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (int scale = 1; scale <= 6; scale++)
    {
      NSString* title = [NSString stringWithFormat:@"%dx (%dp)", scale, 240 * scale];
      [sheet addAction:[UIAlertAction actionWithTitle:title
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction*) {
                                                IOSHost::SetIntSetting("GPU", "ResolutionScale", scale);
                                                IOSHost::CommitSettings();
                                                [tableView reloadData];
                                              }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:L(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
  }
}

@end

//////////////////////////////////////////////////////////////////////////
// Game library
//////////////////////////////////////////////////////////////////////////

@interface DSGameListViewController : UITableViewController <UIDocumentPickerDelegate>
@end

@implementation DSGameListViewController
{
  NSArray<NSString*>* _games;
  BOOL _importingBIOS;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  [self applyTitles];

  self.refreshControl = [[UIRefreshControl alloc] init];
  [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];

  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(refresh)
                                             name:UIApplicationDidBecomeActiveNotification
                                           object:nil];
  [self refresh];
}

- (void)applyTitles
{
  self.title = L(@"library");
  self.navigationItem.leftBarButtonItem =
    [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                     style:UIBarButtonItemStylePlain
                                    target:self
                                    action:@selector(openSettings)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"import")
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(importFiles)];
}

- (void)refresh
{
  NSMutableArray* list = [NSMutableArray array];
  for (const std::string& path : IOSHost::ScanGames())
    [list addObject:@(path.c_str())];
  _games = list;
  [self.tableView reloadData];
  [self.refreshControl endRefreshing];

  if (_games.count == 0)
  {
    UILabel* label = [[UILabel alloc] init];
    label.text = L(@"empty");
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    self.tableView.backgroundView = label;
  }
  else
  {
    self.tableView.backgroundView = nil;
  }
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
  return static_cast<NSInteger>(_games.count);
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"game"];
  if (!cell)
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"game"];

  NSString* path = _games[static_cast<NSUInteger>(indexPath.row)];
  cell.textLabel.text = path.lastPathComponent.stringByDeletingPathExtension;
  cell.detailTextLabel.text = path.pathExtension.uppercaseString;
  cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
  cell.imageView.image = [UIImage systemImageNamed:@"opticaldisc"];
  return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:YES];

  if (!IOSHost::HasBIOS())
  {
    ShowAlert(self, L(@"no_bios_title"), L(@"no_bios_msg"), nil);
    return;
  }

  DSEmulatorViewController* emu =
    [[DSEmulatorViewController alloc] initWithGamePath:_games[static_cast<NSUInteger>(indexPath.row)]];
  [self presentViewController:emu animated:YES completion:nil];
}

- (void)openSettings
{
  DSSettingsViewController* settings = [[DSSettingsViewController alloc] init];
  __weak DSGameListViewController* weakSelf = self;
  settings.onLanguageChanged = ^{
    DSGameListViewController* s = weakSelf;
    if (!s)
      return;
    // Rebuild the navigation stack so the new direction/strings apply everywhere.
    UIWindow* window = s.view.window;
    UINavigationController* nav =
      [[UINavigationController alloc] initWithRootViewController:[[DSGameListViewController alloc] init]];
    nav.navigationBar.prefersLargeTitles = YES;
    window.rootViewController = nav;
  };
  UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:settings];
  [self presentViewController:nav animated:YES completion:nil];
}

- (void)importFiles
{
  UIAlertController* sheet = [UIAlertController alertControllerWithTitle:L(@"import_what")
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"import_games")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) { [self pickFiles:NO]; }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"import_bios")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction*) { [self pickFiles:YES]; }]];
  [sheet addAction:[UIAlertAction actionWithTitle:L(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
  [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickFiles:(BOOL)bios
{
  _importingBIOS = bios;
  UIDocumentPickerViewController* picker =
    [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeData, UTTypeItem ] asCopy:YES];
  picker.allowsMultipleSelection = YES;
  picker.delegate = self;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  const std::string dir = _importingBIOS ? IOSHost::GetBIOSDirectory() : IOSHost::GetGamesDirectory();
  NSString* destDir = @(dir.c_str());
  NSFileManager* fm = NSFileManager.defaultManager;
  [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];

  int count = 0;
  for (NSURL* url in urls)
  {
    NSString* dest = [destDir stringByAppendingPathComponent:url.lastPathComponent];
    [fm removeItemAtPath:dest error:nil];
    NSError* err = nil;
    if ([fm moveItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:&err] ||
        [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dest] error:&err])
    {
      count++;
    }
  }

  [self refresh];
  ShowAlert(self, L(@"import"), [NSString stringWithFormat:L(@"imported"), count], nil);
}

@end

//////////////////////////////////////////////////////////////////////////
// App delegate
//////////////////////////////////////////////////////////////////////////

@interface DSAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation DSAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  ApplyLanguageDirection();

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

  NSString* documents =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* bundle = NSBundle.mainBundle.bundlePath;

  IOSHost::SetEventCallback(&HostEventCallback);
  std::string error;
  const bool ok = IOSHost::Initialize(std::string(documents.fileSystemRepresentation),
                                      std::string(bundle.fileSystemRepresentation), &error);

  UINavigationController* nav =
    [[UINavigationController alloc] initWithRootViewController:[[DSGameListViewController alloc] init]];
  nav.navigationBar.prefersLargeTitles = YES;
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];

  if (!ok)
    ShowAlert(nav, L(@"error"), @(error.c_str()), nil);

  return YES;
}

@end

int main(int argc, char* argv[])
{
  @autoreleasepool
  {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([DSAppDelegate class]));
  }
}
