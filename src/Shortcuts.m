// Extra keyboard shortcuts (off by default; Settings › DayPatch › Shortcuts): tidy the
// sidebar's tabs and switch profiles without the mouse. Each shortcut can be changed
// or cleared in Settings, and is stored as {keyCode, mods, chars} under
// "daypatch.shortcut.<action>".
#import "Common.h"
#import <Carbon/Carbon.h>

NSString *const TweakKeyExtraShortcuts = @"daypatch.extraShortcuts";
NSString *const TweakKeyProfileNumberMods = @"daypatch.profileNumberMods";
static const NSEventModifierFlags kMods = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand;
static BOOL gRecording;

#pragma mark - Scripting

static NSString *quoted(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// Runs a script against this app, inside `tell (first window whose id is …)`.
static NSAppleEventDescriptor *inWindow(NSWindow *w, NSString *body) {
    if (!w.identifier) return nil;
    NSString *src = [NSString stringWithFormat:@"tell application \"%@\"\ntell (first window whose id is \"%@\")\n%@\nend tell\nend tell",
                     quoted(NSBundle.mainBundle.bundlePath), quoted(w.identifier), body];
    NSDictionary *err = nil;
    NSAppleEventDescriptor *r = [[[NSAppleScript alloc] initWithSource:src] executeAndReturnError:&err];
    if (err) NSLog(@"[daypatch] shortcut script failed: %@", err[NSAppleScriptErrorMessage]);
    return r;
}

static NSWindow *browserWindow(void) {
    NSWindow *w = NSApp.keyWindow ?: NSApp.mainWindow;
    return [NSStringFromClass(w.class) isEqualToString:@"Window.PlatformWindow"] ? w : nil;
}

#pragma mark - Profiles

static void focusProfile(NSWindow *w, NSInteger index) {
    inWindow(w, [NSString stringWithFormat:@"if (count of profiles) ≥ %ld then focus profile %ld", (long)index, (long)index]);
}

// +1 / -1 from the active profile, wrapping around.
static void stepProfile(NSWindow *w, NSInteger step, BOOL moveTab) {
    NSString *target = [NSString stringWithFormat:
        @"set n to count of profiles\n"
        "if n < 2 then return\n"
        "set i to index of active profile\n"
        "set p to profile (((i - 1 + %ld + n) mod n) + 1)\n", (long)step];
    inWindow(w, [target stringByAppendingString:moveTab ? @"set t to active tab\nmove t to p\nfocus p\nfocus t" : @"focus p"]);
}

#pragma mark - Actions

typedef void (*TweakShortcutAction)(NSWindow *);
static void nextProfile(NSWindow *w) { stepProfile(w, 1, NO); }
static void previousProfile(NSWindow *w) { stepProfile(w, -1, NO); }
static void moveTabToNextProfile(NSWindow *w) { stepProfile(w, 1, YES); }
static void sortTabs(NSWindow *w) { TweakTabsSortByDomain(w); }
static void groupTabs(NSWindow *w) { TweakTabsGroupByDomain(w); }

static NSDictionary *shortcut(unsigned short code, NSEventModifierFlags mods, NSString *chars) {
    return @{@"keyCode": @(code), @"mods": @(mods), @"chars": chars};
}

NSArray<NSDictionary *> *TweakShortcutActions(void) {
    static NSArray *actions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSEventModifierFlags co = NSEventModifierFlagControl | NSEventModifierFlagOption;
        actions = @[
            @{@"id": @"sortTabs", @"title": @"Sort tabs by domain", @"detail": @"Orders this profile's tabs by site, then title. Pinned tabs and groups stay put.",
              @"run": [NSValue valueWithPointer:sortTabs], @"default": shortcut(kVK_ANSI_S, co, @"s")},
            @{@"id": @"groupTabs", @"title": @"Group tabs by domain", @"detail": @"Puts tabs from the same site (two or more) into a group named after it.",
              @"run": [NSValue valueWithPointer:groupTabs], @"default": shortcut(kVK_ANSI_G, co, @"g")},
            @{@"id": @"nextProfile", @"title": @"Next profile",
              @"run": [NSValue valueWithPointer:nextProfile], @"default": shortcut(kVK_RightArrow, co, @"→")},
            @{@"id": @"previousProfile", @"title": @"Previous profile",
              @"run": [NSValue valueWithPointer:previousProfile], @"default": shortcut(kVK_LeftArrow, co, @"←")},
            @{@"id": @"moveTabToNextProfile", @"title": @"Move tab to next profile", @"detail": @"Takes the current tab with you.",
              @"run": [NSValue valueWithPointer:moveTabToNextProfile], @"default": shortcut(kVK_RightArrow, co | NSEventModifierFlagShift, @"→")},
        ];
    });
    return actions;
}

static NSString *defaultsKey(NSString *actionId) { return [@"daypatch.shortcut." stringByAppendingString:actionId]; }

static NSDictionary *actionWithId(NSString *actionId) {
    for (NSDictionary *a in TweakShortcutActions()) if ([a[@"id"] isEqualToString:actionId]) return a;
    return nil;
}

// The user's shortcut, the default if never set, or nil if cleared.
NSDictionary *TweakShortcutFor(NSString *actionId) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:defaultsKey(actionId)];
    if (!saved) return actionWithId(actionId)[@"default"];
    return [saved isKindOfClass:NSDictionary.class] && [saved count] ? saved : nil;
}

void TweakSetShortcut(NSString *actionId, NSDictionary *shortcut) {
    [NSUserDefaults.standardUserDefaults setObject:shortcut ?: @{} forKey:defaultsKey(actionId)];
    [NSNotificationCenter.defaultCenter postNotificationName:TweakSettingsDidChangeNotification object:nil];
}

NSString *TweakShortcutDisplay(NSDictionary *s) {
    if (!s) return @"";
    NSEventModifierFlags m = [s[@"mods"] unsignedIntegerValue];
    NSMutableString *out = [NSMutableString string];
    if (m & NSEventModifierFlagControl) [out appendString:@"⌃"];
    if (m & NSEventModifierFlagOption) [out appendString:@"⌥"];
    if (m & NSEventModifierFlagShift) [out appendString:@"⇧"];
    if (m & NSEventModifierFlagCommand) [out appendString:@"⌘"];
    [out appendString:[s[@"chars"] uppercaseString]];
    return out;
}

// Profile N is the modifiers (if any) plus the number key N.
NSEventModifierFlags TweakProfileNumberMods(void) {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:TweakKeyProfileNumberMods];
    return v ? [v unsignedIntegerValue] : NSEventModifierFlagControl;
}

BOOL TweakShortcutsHandle(NSEvent *e) {
    if (gRecording || ![TweakSettings boolForKey:TweakKeyExtraShortcuts] || e.isARepeat) return NO;
    NSWindow *w = browserWindow();
    if (!w) return NO;
    NSEventModifierFlags mods = e.modifierFlags & kMods;
    for (NSDictionary *a in TweakShortcutActions()) {
        NSDictionary *s = TweakShortcutFor(a[@"id"]);
        if (!s || [s[@"keyCode"] unsignedShortValue] != e.keyCode || [s[@"mods"] unsignedIntegerValue] != mods) continue;
        ((TweakShortcutAction)[a[@"run"] pointerValue])(w);
        return YES;
    }
    NSEventModifierFlags numberMods = TweakProfileNumberMods();
    NSString *chars = e.charactersIgnoringModifiers;
    if (numberMods && mods == numberMods && chars.length == 1 && [chars characterAtIndex:0] >= '1' && [chars characterAtIndex:0] <= '9') {
        focusProfile(w, [chars characterAtIndex:0] - '0');
        return YES;
    }
    return NO;
}

#pragma mark - Recorder

static NSString *keyName(NSEvent *e) {
    switch (e.keyCode) {
        case kVK_LeftArrow: return @"←";
        case kVK_RightArrow: return @"→";
        case kVK_UpArrow: return @"↑";
        case kVK_DownArrow: return @"↓";
        case kVK_Space: return @"Space";
        case kVK_Return: return @"↩";
        case kVK_Tab: return @"⇥";
        case kVK_F1: return @"F1"; case kVK_F2: return @"F2"; case kVK_F3: return @"F3"; case kVK_F4: return @"F4";
        case kVK_F5: return @"F5"; case kVK_F6: return @"F6"; case kVK_F7: return @"F7"; case kVK_F8: return @"F8";
        case kVK_F9: return @"F9"; case kVK_F10: return @"F10"; case kVK_F11: return @"F11"; case kVK_F12: return @"F12";
    }
    return e.charactersIgnoringModifiers.lowercaseString;
}

@implementation TweakShortcutRecorder {
    id _monitor;
}

- (instancetype)initWithActionId:(NSString *)actionId {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _actionId = [actionId copy];
    self.bezelStyle = NSBezelStyleRounded;
    self.controlSize = NSControlSizeSmall;
    self.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.target = self;
    self.action = @selector(toggleRecording:);
    self.toolTip = @"Click, then press a shortcut with ⌃, ⌥ or ⌘. Delete clears it, Esc cancels.";
    [self.widthAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;
    [self sync];
    return self;
}

- (void)sync {
    NSString *s = TweakShortcutDisplay(TweakShortcutFor(self.actionId));
    self.title = _monitor ? @"Type shortcut…" : (s.length ? s : @"None");
}

- (void)toggleRecording:(id)sender {
    if (_monitor) { [self stop]; return; }
    gRecording = YES;
    __weak typeof(self) weakSelf = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        [weakSelf record:e];
        return nil;
    }];
    [self sync];
}

- (void)record:(NSEvent *)e {
    NSEventModifierFlags mods = e.modifierFlags & kMods;
    if (e.keyCode == kVK_Escape) { [self stop]; return; }
    if (!mods && (e.keyCode == kVK_Delete || e.keyCode == kVK_ForwardDelete)) {
        TweakSetShortcut(self.actionId, nil);
        [self stop];
        return;
    }
    BOOL functionKey = e.keyCode >= kVK_F1 && [keyName(e) hasPrefix:@"F"] && keyName(e).length > 1;
    if (!(mods & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand)) && !functionKey) { NSBeep(); return; }
    TweakSetShortcut(self.actionId, shortcut(e.keyCode, mods, keyName(e)));
    [self stop];
}

- (void)stop {
    if (_monitor) [NSEvent removeMonitor:_monitor];
    _monitor = nil;
    gRecording = NO;
    [self sync];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self stop];
}

@end
