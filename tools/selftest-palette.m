// Dev tool: exercises the ⌘T palette. Output: /tmp/daypatch-palette.txt + PNGs.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static NSView *find(NSView *v, NSString *needle) {
    if ([NSStringFromClass(v.class) containsString:needle]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, needle); if (h) return h; }
    return nil;
}

static void snapshot(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static NSArray<NSString *> *tabURLs(NSWindow *w) {
    for (id sw in [NSApp valueForKey:@"appleScriptWindows"])
        if ([[sw valueForKey:@"windowId"] isEqual:w.identifier]) return [[sw valueForKey:@"appleScriptTabs"] valueForKey:@"URL"];
    return @[];
}

static void key(NSWindow *w, NSString *chars, unsigned short code) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:w.windowNumber context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code] atStart:NO];
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        BOOL (*palette)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADPaletteOpen");
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "ADNavigateWindow");
        NSString *(*urlFor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADURLForWindow");
        navigate(w, @"https://example.com/start");
        after(3, ^{
            NSUInteger tabs0 = tabURLs(w).count;
            BOOL ok = palette(w);
            after(1, ^{
                id fr = w.firstResponder;
                NSView *pop = find(w.contentView.superview, @"DynamicPopover");
                NSRect pf = [pop convertRect:pop.bounds toView:nil];
                [out appendFormat:@"open=%d text=\"%@\" popover=%@ window=%@\n", ok, [fr respondsToSelector:@selector(string)] ? [fr string] : @"?",
                    NSStringFromRect(pf), NSStringFromRect(w.contentView.superview.bounds)];
                snapshot(w, @"/tmp/daypatch-palette-open.png");
                [fr insertText:@"example.org/palette"];
                after(1.2, ^{
                    key(w, @"\r", 36);
                    after(3.5, ^{
                        NSArray *urls = tabURLs(w);
                        [out appendFormat:@"enter: tabs %lu -> %lu, active=%@, start tab kept=%d\n", (unsigned long)tabs0, (unsigned long)urls.count,
                            urlFor(w), [urls containsObject:@"https://example.com/start"]];
                        NSUInteger tabs1 = urls.count;
                        NSString *active1 = urlFor(w);
                        palette(w);
                        after(1, ^{
                            [w.firstResponder insertText:@"should-not-open.example"];
                            after(1, ^{
                                key(w, @"\e", 53);
                                after(2, ^{
                                    [out appendFormat:@"esc: tabs %lu -> %lu, active unchanged=%d, popover=%@\n", (unsigned long)tabs1, (unsigned long)tabURLs(w).count,
                                        [urlFor(w) isEqualToString:active1], find(w.contentView.superview, @"DynamicPopover") ? @"open" : @"closed"];
                                    // Sidebar "New Tab" row.
                                    NSView *row = find(w.contentView.superview, @"NewTabCellView");
                                    if (row) [row mouseDown:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[row convertPoint:NSMakePoint(10, 10) toView:nil]
                                                                         modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1]];
                                    after(1.5, ^{
                                        [out appendFormat:@"new-tab row: row=%@ popover=%@ tabs=%lu\n", row ? @"found" : @"missing",
                                            find(w.contentView.superview, @"DynamicPopover") ? @"open" : @"closed", (unsigned long)tabURLs(w).count];
                                        key(w, @"\e", 53);
                                        [out writeToFile:@"/tmp/daypatch-palette.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });
    });
}
