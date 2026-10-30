// Dev tool: reproduces "type in revealed top bar, press Esc, gap remains".
// Switches to Hidden mode, opens Dia's command bar (what clicking the URL does),
// cancels it, and dumps the pane's children before/after to /tmp/daypatch-gap.txt.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static NSMutableString *out;

static void dump(NSView *v, int depth, int maxDepth) {
    NSRect f = v.frame;
    [out appendFormat:@"%*s%@ (%.0f,%.0f %.0fx%.0f)%@ alpha=%.2f\n", depth * 2, "", NSStringFromClass(v.class),
        f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? @" HIDDEN" : @"", v.alphaValue];
    if (depth < maxDepth) for (NSView *s in v.subviews) dump(s, depth + 1, maxDepth);
}

static NSView *find(NSView *v, NSString *name) {
    if ([NSStringFromClass(v.class) isEqualToString:name]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, name); if (h) return h; }
    return nil;
}

static NSWindow *mainWindow(void) {
    for (NSWindow *w in NSApp.windows) if ([NSStringFromClass(w.class) isEqualToString:@"Window.PlatformWindow"] && w.isVisible) return w;
    return nil;
}

static void snapshot(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void step(NSString *label) {
    NSWindow *w = mainWindow();
    NSView *pane = find(w.contentView.superview, @"ContentPane.ContentPaneView");
    [out appendFormat:@"--- %@ (firstResponder=%@)\n", label, NSStringFromClass(w.firstResponder.class)];
    dump(pane.superview, 0, 3);
}

static NSMenuItem *menuItem(NSString *title) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *i in top.submenu.itemArray)
            if ([i.title isEqualToString:title]) return i;
    return nil;
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Class settings = NSClassFromString(@"ADSettings");
        NSInteger oldMode = (NSInteger)[settings performSelector:@selector(urlBarMode)];
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, @selector(setURLBarMode:), 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSWindow *w = mainWindow();
            [w makeKeyAndOrderFront:nil];
            step(@"hidden mode");
            NSMenuItem *open = menuItem(@"Open Command Bar");
            [NSApp sendAction:open.action to:open.target from:open];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                step(@"command bar open");
                snapshot(w, @"/tmp/daypatch-gap-open.png");
                NSEvent *esc = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                            windowNumber:w.windowNumber context:nil characters:@"\e" charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
                [NSApp postEvent:esc atStart:NO];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    step(@"after escape");
                    snapshot(w, @"/tmp/daypatch-gap-after.png");
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, @selector(setURLBarMode:), oldMode);
                    [out writeToFile:@"/tmp/daypatch-gap.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                });
            });
        });
    });
}
