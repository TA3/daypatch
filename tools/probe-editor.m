// Dev tool: dumps the URL editor popover's view tree (with text/placeholder
// values) after opening the palette. Output: /tmp/daypatch-editor-tree.txt.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
static NSMutableString *out;
static void dump(NSView *v, int d) {
    NSString *extra = @"";
    if ([v isKindOfClass:NSTextView.class]) {
        NSTextView *t = (NSTextView *)v;
        id ph = [t respondsToSelector:@selector(placeholderAttributedString)] ? [t valueForKey:@"placeholderAttributedString"] : nil;
        extra = [NSString stringWithFormat:@" string=\"%@\" placeholder=\"%@\"", t.string, [ph string]];
    } else if ([v isKindOfClass:NSTextField.class]) extra = [NSString stringWithFormat:@" text=\"%@\" ph=\"%@\"", [(NSTextField *)v stringValue], [(NSTextField *)v placeholderString]];
    [out appendFormat:@"%*s%@ %@%@%@\n", d * 2, "", NSStringFromClass(v.class), NSStringFromRect(v.frame), v.hidden ? @" HIDDEN" : @"", extra];
    for (NSView *s in v.subviews) dump(s, d + 1);
}
static NSView *find(NSView *v, NSString *n) { if ([NSStringFromClass(v.class) containsString:n]) return v; for (NSView *s in v.subviews) { NSView *h = find(s, n); if (h) return h; } return nil; }
__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES]; [w makeKeyAndOrderFront:nil];
        ((void (*)(NSWindow *, NSString *))dlsym(RTLD_DEFAULT, "TweakNavigateWindow"))(w, @"https://example.com");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ((BOOL (*)(NSWindow *))dlsym(RTLD_DEFAULT, "TweakPaletteOpen"))(w);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            dump(find(w.contentView.superview, @"DynamicPopover"), 0);
            [out writeToFile:@"/tmp/daypatch-editor-tree.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
        });
    });
}
