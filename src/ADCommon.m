#import "ADCommon.h"
#import <objc/runtime.h>

NSNotificationName const ADSettingsDidChangeNotification = @"ADSettingsDidChangeNotification";
static NSString *const ADKeyMode = @"daypatch.urlBarMode";
static NSString *const ADKeyLastMode = @"daypatch.lastHiddenMode";
NSString *const ADKeyCommandBarStyle = @"daypatch.commandBarStyle";
NSString *const ADKeyRevealOnHover = @"daypatch.revealOnHover";
NSString *const ADKeyCmdLFocusesSidebar = @"daypatch.cmdLFocusesSidebar";
NSString *const ADKeySidebarFullURL = @"daypatch.sidebarShowsFullURL";
NSString *const ADKeySidebarNavButtons = @"daypatch.sidebarShowsNavButtons";

@implementation ADSettings

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
        ADKeyMode: @(ADURLBarModeSidebar),
        ADKeyLastMode: @(ADURLBarModeSidebar),
        ADKeyRevealOnHover: @YES,
        ADKeyCmdLFocusesSidebar: @YES,
        ADKeySidebarFullURL: @NO,
        ADKeySidebarNavButtons: @YES,
        ADKeyHideAI: @YES,
        // Network blocking is opt-in; hiding AI UI only changes what's shown locally.
        ADKeyBlockAI: @NO,
        ADKeyBlockTelemetry: @NO,
        ADKeyDisableOnDeviceAI: @YES,
        ADKeyNoBackgroundNetworking: @NO,
        ADKeyRendererLimit: @0,
        ADKeyNewTabPalette: @YES,
        ADKeyCommandBarStyle: @(ADCommandBarStyleNative),
    }];
}

+ (NSUserDefaults *)d { return NSUserDefaults.standardUserDefaults; }
+ (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:ADSettingsDidChangeNotification object:nil]; }

+ (ADURLBarMode)urlBarMode { return [self.d integerForKey:ADKeyMode]; }
+ (void)setURLBarMode:(ADURLBarMode)mode {
    [self.d setInteger:mode forKey:ADKeyMode];
    if (mode != ADURLBarModeTop) [self.d setInteger:mode forKey:ADKeyLastMode];
    [self changed];
}
+ (void)toggleHiding {
    if (self.urlBarMode == ADURLBarModeTop) [self setURLBarMode:[self.d integerForKey:ADKeyLastMode] ?: ADURLBarModeSidebar];
    else [self setURLBarMode:ADURLBarModeTop];
}

+ (BOOL)revealOnHover { return [self.d boolForKey:ADKeyRevealOnHover]; }
+ (BOOL)cmdLFocusesSidebar { return [self.d boolForKey:ADKeyCmdLFocusesSidebar]; }
+ (BOOL)sidebarShowsFullURL { return [self.d boolForKey:ADKeySidebarFullURL]; }
+ (BOOL)sidebarShowsNavButtons { return [self.d boolForKey:ADKeySidebarNavButtons]; }

+ (BOOL)boolForKey:(NSString *)key { return [self.d boolForKey:key]; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key { [self.d setBool:value forKey:key]; [self changed]; }
+ (void)setString:(NSString *)value forKey:(NSString *)key { [self.d setObject:value forKey:key]; [self changed]; }

@end

#pragma mark - Runtime helpers

NSView *ADChildOfClass(NSView *parent, NSString *className) {
    for (NSView *s in parent.subviews)
        if ([NSStringFromClass(s.class) isEqualToString:className]) return s;
    return nil;
}

NSView *ADDescendantOfClass(NSView *root, NSString *className) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (NSView *s in root.subviews) {
        NSView *hit = ADDescendantOfClass(s, className);
        if (hit) return hit;
    }
    return nil;
}

Class ADFindClass(NSString *prefix, NSString *suffix) {
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

IMP ADHook(Class cls, SEL sel, IMP imp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    if (class_addMethod(cls, sel, imp, method_getTypeEncoding(m))) return method_getImplementation(m);
    return method_setImplementation(m, imp);
}

#pragma mark - Scripting bridge

id ADActiveTabForWindow(NSWindow *window) {
    NSString *wid = window.identifier;
    if (!wid) return nil;
    @try {
        for (id sw in [NSApp valueForKey:@"appleScriptWindows"])
            if ([[sw valueForKey:@"windowId"] isEqual:wid]) return [sw valueForKey:@"activeTab"];
    } @catch (__unused NSException *e) {}
    return nil;
}

NSString *ADURLForWindow(NSWindow *window) {
    @try {
        id u = [ADActiveTabForWindow(window) valueForKey:@"URL"];
        return [u isKindOfClass:NSString.class] ? u : nil;
    } @catch (__unused NSException *e) { return nil; }
}

NSString *ADResolveInput(NSString *input) {
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

void ADNavigateWindow(NSWindow *window, NSString *input) {
    NSString *url = ADResolveInput(input);
    id tab = ADActiveTabForWindow(window);
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
void ADOpenInNewTab(NSWindow *window, NSString *url) {
    if (!window.identifier || !url.length) return;
    runScript([NSString stringWithFormat:@"tell application id \"company.thebrowser.dia\"\n"
               "  tell (first window whose id is \"%@\") to make new tab with properties {URL:\"%@\"}\n"
               "end tell", scriptString(window.identifier), scriptString(url)]);
}

void ADFocusTab(NSString *windowId, NSString *tabId) {
    if (!windowId || !tabId) return;
    runScript([NSString stringWithFormat:@"tell application id \"company.thebrowser.dia\"\n"
               "  focus (first tab of (first window whose id is \"%@\") whose id is \"%@\")\n"
               "end tell", scriptString(windowId), scriptString(tabId)]);
}

ADCommandBarStyle ADCommandBarCurrentStyle(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:ADKeyCommandBarStyle];
}
