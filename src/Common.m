#import "Common.h"
#import <objc/runtime.h>

NSNotificationName const TweakSettingsDidChangeNotification = @"TweakSettingsDidChangeNotification";
static NSString *const TweakKeyMode = @"daypatch.urlBarMode";
static NSString *const TweakKeyLastMode = @"daypatch.lastHiddenMode";
NSString *const TweakKeyCommandBarStyle = @"daypatch.commandBarStyle";
NSString *const TweakKeyRevealOnHover = @"daypatch.revealOnHover";
NSString *const TweakKeyCmdLFocusesSidebar = @"daypatch.cmdLFocusesSidebar";
NSString *const TweakKeySidebarFullURL = @"daypatch.sidebarShowsFullURL";
NSString *const TweakKeySidebarNavButtons = @"daypatch.sidebarShowsNavButtons";

@implementation TweakSettings

+ (void)initialize {
    // One-time move from the project's previous name: copy "arcedDia.*" settings.
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:@"daypatch.migrated"]) {
        NSDictionary *all = d.dictionaryRepresentation;
        for (NSString *k in all)
            if ([k hasPrefix:@"arcedDia."]) {
                NSString *nk = [@"daypatch." stringByAppendingString:[k substringFromIndex:9]];
                if (![d objectForKey:nk]) [d setObject:all[k] forKey:nk];
            }
        [d setBool:YES forKey:@"daypatch.migrated"];
    }
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        TweakKeyMode: @(TweakURLBarModeSidebar),
        TweakKeyLastMode: @(TweakURLBarModeSidebar),
        TweakKeyRevealOnHover: @NO,
        TweakKeyCmdLFocusesSidebar: @YES,
        TweakKeySidebarFullURL: @NO,
        TweakKeySidebarNavButtons: @YES,
        TweakKeyHideAI: @YES,
        // Network blocking is opt-in; hiding AI UI only changes what's shown locally.
        TweakKeyBlockAI: @NO,
        TweakKeyBlockTelemetry: @NO,
        TweakKeyDisableOnDeviceAI: @YES,
        TweakKeyNoBackgroundNetworking: @NO,
        TweakKeyRendererLimit: @0,
        TweakKeyNewTabPalette: @YES,
        TweakKeyCommandBarStyle: @(TweakCommandBarStyleNative),
    }];
}

+ (NSUserDefaults *)d { return NSUserDefaults.standardUserDefaults; }
+ (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:TweakSettingsDidChangeNotification object:nil]; }

+ (TweakURLBarMode)urlBarMode { return [self.d integerForKey:TweakKeyMode]; }
+ (void)setURLBarMode:(TweakURLBarMode)mode {
    [self.d setInteger:mode forKey:TweakKeyMode];
    if (mode != TweakURLBarModeTop) [self.d setInteger:mode forKey:TweakKeyLastMode];
    [self changed];
}
+ (void)toggleHiding {
    if (self.urlBarMode == TweakURLBarModeTop) [self setURLBarMode:[self.d integerForKey:TweakKeyLastMode] ?: TweakURLBarModeSidebar];
    else [self setURLBarMode:TweakURLBarModeTop];
}

+ (BOOL)revealOnHover { return [self.d boolForKey:TweakKeyRevealOnHover]; }
+ (BOOL)cmdLFocusesSidebar { return [self.d boolForKey:TweakKeyCmdLFocusesSidebar]; }
+ (BOOL)sidebarShowsFullURL { return [self.d boolForKey:TweakKeySidebarFullURL]; }
+ (BOOL)sidebarShowsNavButtons { return [self.d boolForKey:TweakKeySidebarNavButtons]; }

+ (BOOL)boolForKey:(NSString *)key { return [self.d boolForKey:key]; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key { [self.d setBool:value forKey:key]; [self changed]; }
+ (void)setString:(NSString *)value forKey:(NSString *)key { [self.d setObject:value forKey:key]; [self changed]; }

@end

#pragma mark - Runtime helpers

NSView *TweakChildOfClass(NSView *parent, NSString *className) {
    for (NSView *s in parent.subviews)
        if ([NSStringFromClass(s.class) isEqualToString:className]) return s;
    return nil;
}

NSView *TweakDescendantOfClass(NSView *root, NSString *className) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (NSView *s in root.subviews) {
        NSView *hit = TweakDescendantOfClass(s, className);
        if (hit) return hit;
    }
    return nil;
}

Class TweakFindClass(NSString *prefix, NSString *suffix) {
    // Exact name first; private Swift classes carry a per-build hash, so fall back to a scan.
    if (!suffix.length) return NSClassFromString(prefix);
    unsigned n = 0;
    Class *all = objc_copyClassList(&n);
    Class found = nil;
    for (unsigned i = 0; i < n && !found; i++) {
        const char *name = class_getName(all[i]);
        if (strncmp(name, prefix.UTF8String, prefix.length) != 0) continue;
        NSString *s = @(name);
        if ([s hasSuffix:suffix]) found = all[i];
    }
    free(all);
    return found;
}

IMP TweakHook(Class cls, SEL sel, IMP imp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    if (class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) return method_getImplementation(m);
    return method_setImplementation(m, imp);
}

#pragma mark - Scripting bridge

id TweakActiveTabForWindow(NSWindow *window) {
    NSString *wid = window.identifier;
    if (!wid) return nil;
    @try {
        for (id sw in [NSApp valueForKey:@"appleScriptWindows"])
            if ([[sw valueForKey:@"windowId"] isEqual:wid]) return [sw valueForKey:@"activeTab"];
    } @catch (__unused NSException *e) {}
    return nil;
}

NSString *TweakURLForWindow(NSWindow *window) {
    @try {
        id u = [TweakActiveTabForWindow(window) valueForKey:@"URL"];
        return [u isKindOfClass:NSString.class] ? u : nil;
    } @catch (__unused NSException *e) { return nil; }
}

NSString *TweakResolveInput(NSString *input) {
    NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return nil;
    NSRegularExpression *scheme = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z][a-zA-Z0-9+.-]*:(//)?[^\\s]*$" options:0 error:nil];
    BOOL hasSpace = [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound;
    if (!hasSpace && [scheme firstMatchInString:s options:0 range:NSMakeRange(0, s.length)] &&
        ([s containsString:@"://"] || [s hasPrefix:@"about:"] || [s hasPrefix:@"chrome:"] || [s hasPrefix:@"file:"] || [s hasPrefix:@"mailto:"]))
        return s;
    NSString *host = [s componentsSeparatedByString:@"/"].firstObject;
    BOOL local = [host hasPrefix:@"localhost"] || [host hasPrefix:@"127."] || [host hasSuffix:@".localhost"] || [host hasSuffix:@".test"];
    if (!hasSpace && (local || ([host containsString:@"."] && ![host hasSuffix:@"."])))
        return [(local ? @"http://" : @"https://") stringByAppendingString:s];
    NSString *template = @"https://www.google.com/search?q=%@";  // only reached for non-URL input
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+?#"];
    return [NSString stringWithFormat:template, [s stringByAddingPercentEncodingWithAllowedCharacters:allowed]];
}

void TweakNavigateWindow(NSWindow *window, NSString *input) {
    NSString *url = TweakResolveInput(input);
    id tab = TweakActiveTabForWindow(window);
    if (!url || !tab) return;
    @try { [tab setValue:url forKey:@"URL"]; }
    @catch (NSException *e) { NSLog(@"[daypatch] navigate failed: %@", e); }
}

static void runScript(NSString *src) {
    NSDictionary *err = nil;
    [[[NSAppleScript alloc] initWithSource:src] executeAndReturnError:&err];
    if (err) NSLog(@"[daypatch] script failed: %@", err[NSAppleScriptErrorMessage]);
}

static NSString *scriptString(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// Dia's scripting interface, called in-process (AppleEvents to self need no permission).
void TweakOpenInNewTab(NSWindow *window, NSString *url) {
    if (!window.identifier || !url.length) return;
    runScript([NSString stringWithFormat:@"tell application id \"company.thebrowser.dia\"\n"
               "  tell (first window whose id is \"%@\") to make new tab with properties {URL:\"%@\"}\n"
               "end tell", scriptString(window.identifier), scriptString(url)]);
}

void TweakFocusTab(NSString *windowId, NSString *tabId) {
    if (!windowId || !tabId) return;
    runScript([NSString stringWithFormat:@"tell application id \"company.thebrowser.dia\"\n"
               "  focus (first tab of (first window whose id is \"%@\") whose id is \"%@\")\n"
               "end tell", scriptString(windowId), scriptString(tabId)]);
}

TweakCommandBarStyle TweakCommandBarCurrentStyle(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:TweakKeyCommandBarStyle];
}
