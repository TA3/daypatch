// Shared helpers for daypatch.
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, TweakURLBarMode) {
    TweakURLBarModeTop = 0,      // Dia's stock bar above each pane
    TweakURLBarModeHidden = 1,   // bar hidden, optionally revealed on hover
    TweakURLBarModeSidebar = 2,  // bar hidden, URL field shown in the tab sidebar
};

// Settings (stored in Dia's own defaults domain under "daypatch.*").
@interface TweakSettings : NSObject
+ (TweakURLBarMode)urlBarMode;
+ (void)setURLBarMode:(TweakURLBarMode)mode;
+ (BOOL)revealOnHover;
+ (BOOL)cmdLFocusesSidebar;
+ (BOOL)sidebarShowsFullURL;
+ (BOOL)sidebarShowsNavButtons;
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (void)toggleHiding;                    // ⌃⌘U
@end

extern NSNotificationName const TweakSettingsDidChangeNotification;
extern NSString *const TweakKeyRevealOnHover;
extern NSString *const TweakKeyCmdLFocusesSidebar;
extern NSString *const TweakKeySidebarFullURL;
extern NSString *const TweakKeySidebarNavButtons;
extern NSString *const TweakKeyHideAI;
extern NSString *const TweakKeyBlockAI;
extern NSString *const TweakKeyBlockTelemetry;
extern NSString *const TweakKeyDisableOnDeviceAI;
extern NSString *const TweakKeyNoBackgroundNetworking;
extern NSString *const TweakKeyRendererLimit;
extern NSString *const TweakKeyNewTabPalette;
extern NSString *const TweakKeyCommandBarStyle;

typedef NS_ENUM(NSInteger, TweakCommandBarStyle) {
    TweakCommandBarStyleOff = 0,       // Dia's defaults
    TweakCommandBarStyleDiaEditor = 1, // Dia's own editor, re-anchored (TweakPalette)
    TweakCommandBarStyleNative = 2,    // daypatch's Arc-style command bar
};

// Runtime helpers.
NSView *TweakChildOfClass(NSView *parent, NSString *className);
NSView *TweakDescendantOfClass(NSView *root, NSString *className);
Class TweakFindClass(NSString *prefix, NSString *suffix);
// Replaces -[cls sel] with imp, returning the previous implementation
// (the inherited one if cls didn't override sel).
IMP TweakHook(Class cls, SEL sel, IMP imp);

// Dia scripting bridge: the active tab object for a window (DiaAppleScriptTab), or nil.
id TweakActiveTabForWindow(NSWindow *window);
NSString *TweakURLForWindow(NSWindow *window);
void TweakNavigateWindow(NSWindow *window, NSString *input);
void TweakOpenInNewTab(NSWindow *window, NSString *url);
void TweakFocusTab(NSString *windowId, NSString *tabId);
NSString *TweakResolveInput(NSString *input);

// Modules.
void TweakNavBarInstall(void);
BOOL TweakNavBarShouldHideInWindow(NSWindow *window);
void TweakNavBarPerform(NSWindow *window, NSInteger index);  // 0 back, 1 forward, 2 reload
BOOL TweakNavBarOpenEditor(NSWindow *window, NSRect anchorInWindow);  // Dia's URL editor, placed at anchor
void TweakSidebarInstall(void);
BOOL TweakSidebarHasURLBar(NSWindow *window);
BOOL TweakSidebarFocusURLBar(NSWindow *window);
void TweakPreferencesInstall(void);
void TweakPrivacyPatchArgv(void);   // call before main()
void TweakPrivacyInstall(void);
NSUInteger TweakBlockedRequestCount(void);
NSArray<NSString *> *TweakAIHosts(void);
NSArray<NSString *> *TweakTelemetryHosts(void);
void TweakPerformanceInstall(void);   // call before main()
NSArray<NSString *> *TweakPerformanceSwitches(void);
void TweakPaletteInstall(void);
void TweakHandoffInstall(void);       // "Use Passkeys in Original Dia…"
BOOL TweakPaletteOpen(NSWindow *window);          // ⌘T: Dia's editor centred, commits open a new tab
void TweakPaletteEditorClosed(NSWindow *window);
BOOL TweakCommandBarShow(NSWindow *window, BOOL newTab);
TweakCommandBarStyle TweakCommandBarCurrentStyle(void);
NSString *TweakPatchVersion(void);
void TweakHealthWrite(void);
void TweakKickCompanionOnQuit(void);
