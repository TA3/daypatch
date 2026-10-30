// Dev tool: checks the Settings title bar fill on scroll and the command bar's
// ranking for "g". Output: /tmp/daypatch-polish.txt and /tmp/daypatch-polish-*.png.
#import <AppKit/AppKit.h>
#include <dlfcn.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }
static NSView *find(NSView *v, NSString *n) { if ([NSStringFromClass(v.class) containsString:n]) return v; for (NSView *s in v.subviews) { NSView *h = find(s, n); if (h) return h; } return nil; }
static void snap(NSWindow *w, NSString *p) {
    NSView *v = w.contentView.superview ?: w.contentView;
    NSBitmapImageRep *r = [v bitmapImageRepForCachingDisplayInRect:v.bounds]; [v cacheDisplayInRect:v.bounds toBitmapImageRep:r];
    [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:p atomically:YES];
}
static NSString *titlebarState(NSWindow *w) {
    // Where the DayPatch pane's scroll area starts vs. where the title bar ends (window coords).
    NSView *sv = find(find(w.contentView, @"ADPrefsPane"), @"NSScrollView");
    if (sv) return [NSString stringWithFormat:@"scroll top=%.0f titlebar bottom=%.0f", NSMaxY([sv convertRect:sv.bounds toView:nil]), NSMaxY(w.contentLayoutRect)];
    NSMutableArray *states = [NSMutableArray array];
    NSMutableArray *q = [NSMutableArray arrayWithObject:w.contentView.superview];
    while (q.count) { NSView *v = q.lastObject; [q removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"NSTitlebarBackgroundView"]) [states addObject:[NSString stringWithFormat:@"x=%.0f:%@", NSMinX(v.frame), v.hidden ? @"hidden" : @"shown"]];
        [q addObjectsFromArray:v.subviews]; }
    return [states componentsJoinedByString:@" "];
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(9, ^{
        for (NSMenuItem *i in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray)
            if ([i.keyEquivalent isEqualToString:@","]) [NSApp sendAction:i.action to:i.target from:i];
        after(2, ^{
            NSWindow *p = nil;
            for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) containsString:@"Preferences"] && x.isVisible) p = x;
            NSTableView *t = (NSTableView *)find(p.contentView, @"NSTableView");
            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:t.numberOfRows - 1] byExtendingSelection:NO];
            after(1, ^{
                NSScrollView *sv = (NSScrollView *)find(find(p.contentView, @"ADPrefsPane"), @"NSScrollView");
                [out appendFormat:@"top:      %@\n", titlebarState(p)];
                snap(p, @"/tmp/daypatch-polish-top.png");
                [sv.contentView scrollToPoint:NSMakePoint(0, 220)]; [sv reflectScrolledClipView:sv.contentView];
                after(0.6, ^{
                    [out appendFormat:@"scrolled: %@\n", titlebarState(p)];
                    snap(p, @"/tmp/daypatch-polish-scrolled.png");
                    [sv.contentView scrollToPoint:NSMakePoint(0, -sv.contentView.contentInsets.top)]; [sv reflectScrolledClipView:sv.contentView];
                    after(0.6, ^{
                        [out appendFormat:@"back top: %@\n", titlebarState(p)];
                        [sv.contentView scrollToPoint:NSMakePoint(0, 220)]; [sv reflectScrolledClipView:sv.contentView];
                        after(0.4, ^{
                            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
                            after(0.8, ^{
                                [out appendFormat:@"left pane while scrolled: %@\n", titlebarState(p)];
                                [p close];
                                // Command bar: "g".
                                NSWindow *w = nil;
                                for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
                                [NSApp activateIgnoringOtherApps:YES]; [w makeKeyAndOrderFront:nil];
                                ((BOOL (*)(NSWindow *, BOOL))dlsym(RTLD_DEFAULT, "ADCommandBarShow"))(w, YES);
                                after(0.8, ^{
                                    id bar = [NSClassFromString(@"ADCommandBar") performSelector:@selector(shared)];
                                    NSTextView *ed = (NSTextView *)[[bar valueForKey:@"field"] currentEditor];
                                    [ed insertText:@"g"];
                                    after(1.5, ^{
                                        [out appendFormat:@"command bar 'g': field=\"%@\"\n", ed.string];
                                        NSArray *kinds = @[@"search", @"url", @"command", @"page", @"tab", @"bookmark", @"history"];
                                        int n = 0;
                                        for (id it in [[bar valueForKey:@"results"] valueForKey:@"items"])
                                            if (n++ < 4) [out appendFormat:@"   %@  %@ — %@\n", kinds[[[it valueForKey:@"kind"] integerValue]], [it valueForKey:@"title"], [it valueForKey:@"url"]];
                                        snap([bar valueForKey:@"panel"], @"/tmp/daypatch-polish-bar.png");
                                        [out writeToFile:@"/tmp/daypatch-polish.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
