// Dev tool: inspects Dia's AssistantBarView (the stock URL field) to see whether
// it can be re-hosted in the sidebar. Focuses it, types "git", and records where
// the suggestions appear. Output: /tmp/daypatch-bar.txt and /tmp/daypatch-bar*.png.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;

static NSView *find(NSView *v, NSString *name) {
    if ([NSStringFromClass(v.class) isEqualToString:name]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, name); if (h) return h; }
    return nil;
}

static void dump(NSView *v, int depth, int maxDepth) {
    NSRect f = v.frame;
    [out appendFormat:@"%*s%@ (%.0f,%.0f %.0fx%.0f)%@ tamic=%d constraints=%lu\n", depth * 2, "", NSStringFromClass(v.class),
        f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? @" HIDDEN" : @"",
        v.translatesAutoresizingMaskIntoConstraints, (unsigned long)v.constraints.count];
    if (depth < maxDepth) for (NSView *s in v.subviews) dump(s, depth + 1, maxDepth);
}

static void snapshot(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview ?: w.contentView;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "TweakNavigateWindow");
        navigate(w, @"https://example.com");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSView *bar = find(w.contentView.superview, @"NavigationBar.AssistantBarView");
        [out appendFormat:@"bar=%@ superview chain:\n", bar];
        for (NSView *s = bar.superview; s && ![NSStringFromClass(s.class) hasPrefix:@"ContentPane"]; s = s.superview)
            [out appendFormat:@"  ^ %@ tamic=%d constraints=%lu\n", NSStringFromClass(s.class), s.translatesAutoresizingMaskIntoConstraints, (unsigned long)s.constraints.count];
        for (NSLayoutConstraint *c in bar.superview.constraints)
            if (c.firstItem == bar || c.secondItem == bar) [out appendFormat:@"  constraint %@\n", c];
        dump(bar, 0, 6);

        NSView *text = find(bar, @"NavigationBar.TextView");
        [out appendFormat:@"text view %@ isTextView=%d accepts=%d\n", NSStringFromClass(text.class), [text isKindOfClass:NSTextView.class], text.acceptsFirstResponder];
        // Click it the way a user would.
        NSPoint p = [text convertPoint:NSMakePoint(NSMidX(text.bounds), NSMidY(text.bounds)) toView:nil];
        NSEventType types[] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp};
        for (int i = 0; i < 2; i++) {
            NSEvent *e = [NSEvent mouseEventWithType:types[i] location:p modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                        windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            [w sendEvent:e];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            id fr = w.firstResponder;
            [out appendFormat:@"after click firstResponder=%@\n", NSStringFromClass([fr class])];
            if ([fr respondsToSelector:@selector(insertText:)]) [fr insertText:@"git"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [out appendString:@"--- after typing\n"];
                for (NSWindow *x in NSApp.windows)
                    if (x.isVisible) [out appendFormat:@"WINDOW %@ frame=%@ parent=%@\n", NSStringFromClass(x.class), NSStringFromRect(x.frame), NSStringFromClass(x.parentWindow.class)];
                NSView *sug = find(w.contentView.superview, @"BoostCommandBar.SuggestionsView");
                NSView *bar2 = find(w.contentView.superview, @"NavigationBar.AssistantBarView");
                [out appendFormat:@"suggestions=%@ frame-in-window=%@\n", NSStringFromClass(sug.class), NSStringFromRect([sug convertRect:sug.bounds toView:nil])];
                for (NSView *s = sug.superview; s; s = s.superview) [out appendFormat:@"  ^ %@\n", NSStringFromClass(s.class)];
                dump(bar2, 0, 3);
                snapshot(w, @"/tmp/daypatch-bar-typing.png");
                [out writeToFile:@"/tmp/daypatch-bar.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
            });
        });
        });
    });
}
