// Dev tool: (1) logs ArcWebContentsNavigationController loads triggered by the URL
// editor, (2) checks that in-process AppleScript can open a new tab with a URL.
// Output: /tmp/daypatch-load.txt.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static id (*origLoad)(id, SEL, id, id, long, BOOL, BOOL);
static id hookedLoad(id self, SEL _cmd, id url, id origin, long transition, BOOL fromAddressBar, BOOL typedHttp) {
    id r = origLoad(self, _cmd, url, origin, transition, fromAddressBar, typedHttp);
    [out appendFormat:@"LOAD url=%@ (%@) origin=%@ transition=%ld fromAddressBar=%d -> %@\n", url, NSStringFromClass([url class]), origin, transition, fromAddressBar, NSStringFromClass([r class])];
    [out appendFormat:@"     stack: %@\n", [[NSThread.callStackSymbols subarrayWithRange:NSMakeRange(1, 6)] valueForKey:@"description"]];
    return r;
}

static NSInteger tabCount(NSWindow *w) {
    for (id sw in [NSApp valueForKey:@"appleScriptWindows"])
        if ([[sw valueForKey:@"windowId"] isEqual:w.identifier]) return [[sw valueForKey:@"appleScriptTabs"] count];
    return -1;
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    Class c = NSClassFromString(@"ArcWebContentsNavigationController");
    Method m = class_getInstanceMethod(c, @selector(load:initiatorOrigin:transition:fromAddressBar:typedWithHttpScheme:));
    origLoad = (void *)method_setImplementation(m, (IMP)hookedLoad);

    after(8, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        BOOL (*openEditor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADSidebarFocusURLBar");
        [out appendString:@"--- editor commit\n"];
        openEditor(w);
        after(1, ^{
            id fr = w.firstResponder;
            [fr insertText:@"example.net"];
            after(1.2, ^{
                [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                             windowNumber:w.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36] atStart:NO];
                after(3, ^{
                    [out appendString:@"--- applescript new tab\n"];
                    NSInteger before = tabCount(w);
                    NSString *src = [NSString stringWithFormat:@"tell application id \"company.thebrowser.dia\"\n"
                                     "  tell (first window whose id is \"%@\") to make new tab with properties {URL:\"https://example.org/as\"}\n"
                                     "end tell", w.identifier];
                    NSDictionary *err = nil;
                    NSAppleEventDescriptor *res = [[[NSAppleScript alloc] initWithSource:src] executeAndReturnError:&err];
                    after(3, ^{
                        void *urlFor = dlsym(RTLD_DEFAULT, "ADURLForWindow");
                        [out appendFormat:@"result=%@ err=%@ tabs %ld -> %ld active=%@\n", res, err, (long)before, (long)tabCount(w), ((NSString *(*)(NSWindow *))urlFor)(w)];
                        [out writeToFile:@"/tmp/daypatch-load.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    });
                });
            });
        });
    });
}
