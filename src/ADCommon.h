// Shared helpers for daypatch.
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ADURLBarMode) {
    ADURLBarModeTop = 0,      // Dia's stock bar above each pane
    ADURLBarModeHidden = 1,   // bar hidden, optionally revealed on hover
    ADURLBarModeSidebar = 2,  // bar hidden, URL field shown in the tab sidebar
};

// Settings (stored in Dia's own defaults domain under "daypatch.*").
@interface ADSettings : NSObject
+ (ADURLBarMode)urlBarMode;
+ (void)setURLBarMode:(ADURLBarMode)mode;
+ (BOOL)revealOnHover;
+ (BOOL)cmdLFocusesSidebar;
+ (BOOL)sidebarShowsFullURL;
+ (BOOL)sidebarShowsNavButtons;
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (void)toggleHiding;                    // ⌃⌘U
@end

extern NSNotificationName const ADSettingsDidChangeNotification;
extern NSString *const ADKeyRevealOnHover;
extern NSString *const ADKeyCmdLFocusesSidebar;
extern NSString *const ADKeySidebarFullURL;
extern NSString *const ADKeySidebarNavButtons;
extern NSString *const ADKeyHideAI;
extern NSString *const ADKeyBlockAI;
extern NSString *const ADKeyBlockTelemetry;
extern NSString *const ADKeyDisableOnDeviceAI;
extern NSString *const ADKeyNoBackgroundNetworking;
extern NSString *const ADKeyRendererLimit;
extern NSString *const ADKeyNewTabPalette;
extern NSString *const ADKeyCommandBarStyle;

typedef NS_ENUM(NSInteger, ADCommandBarStyle) {
    ADCommandBarStyleOff = 0,       // Dia's defaults
    ADCommandBarStyleDiaEditor = 1, // Dia's own editor, re-anchored (ADPalette)
    ADCommandBarStyleNative = 2,    // daypatch's Arc-style command bar
};

// Runtime helpers.
NSView *ADChildOfClass(NSView *parent, NSString *className);
NSView *ADDescendantOfClass(NSView *root, NSString *className);
Class ADFindClass(NSString *prefix, NSString *suffix);
// Replaces -[cls sel] with imp, returning the previous implementation
// (the inherited one if cls didn't override sel).
IMP ADHook(Class cls, SEL sel, IMP imp);

// Dia scripting bridge: the active tab object for a window (DiaAppleScriptTab), or nil.
id ADActiveTabForWindow(NSWindow *window);
NSString *ADURLForWindow(NSWindow *window);
void ADNavigateWindow(NSWindow *window, NSString *input);
void ADOpenInNewTab(NSWindow *window, NSString *url);
void ADFocusTab(NSString *windowId, NSString *tabId);
NSString *ADResolveInput(NSString *input);

// Modules.
void ADNavBarInstall(void);
BOOL ADNavBarShouldHideInWindow(NSWindow *window);
void ADNavBarPerform(NSWindow *window, NSInteger index);  // 0 back, 1 forward, 2 reload
BOOL ADNavBarOpenEditor(NSWindow *window, NSRect anchorInWindow);  // Dia's URL editor, placed at anchor
void ADSidebarInstall(void);
BOOL ADSidebarHasURLBar(NSWindow *window);
BOOL ADSidebarFocusURLBar(NSWindow *window);
void ADPreferencesInstall(void);
void ADPrivacyPatchArgv(void);   // call before main()
void ADPrivacyInstall(void);
NSUInteger ADBlockedRequestCount(void);
NSArray<NSString *> *ADAIHosts(void);
NSArray<NSString *> *ADTelemetryHosts(void);
void ADPerformanceInstall(void);   // call before main()
NSArray<NSString *> *ADPerformanceSwitches(void);
void ADPaletteInstall(void);
BOOL ADPaletteOpen(NSWindow *window);          // ⌘T: Dia's editor centred, commits open a new tab
void ADPaletteEditorClosed(NSWindow *window);
BOOL ADCommandBarShow(NSWindow *window, BOOL newTab);
ADCommandBarStyle ADCommandBarCurrentStyle(void);
NSString *ADPatchVersion(void);
void ADHealthWrite(void);
void ADKickCompanionOnQuit(void);
