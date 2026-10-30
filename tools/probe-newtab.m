// Dev tool: does Dia's URL editor open its result in a new tab with a modifier?
// For each of ⌘↩, ⌥↩, ⇧↩: open the editor, type a URL, press the combo, then
// record tab count and the active URL. Output: /tmp/daypatch-newtab.txt.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static NSInteger tabCount(NSWindow *w) {
    for (id sw in [NSApp valueForKey:@"appleScriptWindows"])
        if ([[sw valueForKey:@"windowId"] isEqual:w.identifier]) return [[sw valueForKey:@"appleScriptTabs"] count];
    return -1;
}

static void runCase(NSWindow *w, NSArray *cases, NSUInteger i) {
    if (i >= cases.count) { [out writeToFile:@"/tmp/daypatch-newtab.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
    NSString *name = cases[i][0];
    NSEventModifierFlags mods = [cases[i][1] unsignedIntegerValue];
    NSString *(*urlFor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADURLForWindow");
    BOOL (*openEditor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADSidebarFocusURLBar");
    NSInteger before = tabCount(w);
    NSString *beforeURL = urlFor(w);
    openEditor(w);
    after(1, ^{
        id fr = w.firstResponder;
        NSString *target = [NSString stringWithFormat:@"example.org/?case=%lu", (unsigned long)i];
        if ([fr respondsToSelector:@selector(insertText:)]) [fr insertText:target];
        after(1.2, ^{
            NSEvent *ret = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:NSProcessInfo.processInfo.systemUptime
                                        windowNumber:w.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
            [NSApp postEvent:ret atStart:NO];
            after(3, ^{
                [out appendFormat:@"%@: tabs %ld -> %ld, active %@ -> %@\n", name, (long)before, (long)tabCount(w), beforeURL, urlFor(w)];
                // Reset: back to the starting page in whatever tab is active.
                void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "ADNavigateWindow");
                navigate(w, @"https://example.com");
                after(2.5, ^{ runCase(w, cases, i + 1); });
            });
        });
    });
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "ADNavigateWindow");
        navigate(w, @"https://example.com");
        // Menu items that might mean "open in new tab" while editing.
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) for (NSMenuItem *it in top.submenu.itemArray)
            if ([it.title.lowercaseString containsString:@"new tab"]) [out appendFormat:@"MENU %@ > %@ [%@ mods=%lx] action=%@\n", top.title, it.title, it.keyEquivalent, (unsigned long)it.keyEquivalentModifierMask, NSStringFromSelector(it.action)];
        after(3, ^{
            runCase(w, @[@[@"plain ↩", @0], @[@"⌘↩", @(NSEventModifierFlagCommand)], @[@"⌥↩", @(NSEventModifierFlagOption)], @[@"⇧↩", @(NSEventModifierFlagShift)]], 0);
        });
    });
}
