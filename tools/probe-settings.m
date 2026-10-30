// Dev tool: opens Settings, snapshots Dia's own Tabs pane and the daypatch pane,
// and dumps the Tabs pane's view frames for matching row metrics.
// Output: /tmp/settings.txt, /tmp/settings-dia.png, /tmp/settings-daypatch.png.
#import <AppKit/AppKit.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static NSView *find(NSView *v, NSString *n) {
    if ([NSStringFromClass(v.class) containsString:n]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, n); if (h) return h; }
    return nil;
}

static void dump(NSView *v, int d, int max) {
    if (v.hidden) return;
    NSString *extra = [v isKindOfClass:NSTextField.class] ? [NSString stringWithFormat:@" \"%@\" font=%.1f", [(NSTextField *)v stringValue], [(NSTextField *)v font].pointSize] : @"";
    if ([v isKindOfClass:NSStackView.class]) {
        NSStackView *s = (NSStackView *)v;
        extra = [NSString stringWithFormat:@" spacing=%.0f insets=(%.0f,%.0f,%.0f,%.0f)", s.spacing, s.edgeInsets.top, s.edgeInsets.left, s.edgeInsets.bottom, s.edgeInsets.right];
    }
    if (v.layer.cornerRadius > 0) extra = [extra stringByAppendingFormat:@" radius=%.0f", v.layer.cornerRadius];
    [out appendFormat:@"%*s%@ %@%@\n", d * 2, "", NSStringFromClass(v.class), NSStringFromRect(v.frame), extra];
    if (d < max) for (NSView *s in v.subviews) dump(s, d + 1, max);
}

static void snap(NSWindow *w, NSString *p) {
    NSView *v = w.contentView.superview;
    NSBitmapImageRep *r = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:r];
    [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:p atomically:YES];
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        for (NSMenuItem *i in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray)
            if ([i.keyEquivalent isEqualToString:@","]) [NSApp sendAction:i.action to:i.target from:i];
        after(2, ^{
            NSWindow *p = nil;
            for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) containsString:@"Preferences"] && x.isVisible) p = x;
            NSTableView *t = (NSTableView *)find(p.contentView, @"NSTableView");
            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];  // Tabs
            after(1.5, ^{
                snap(p, @"/tmp/settings-dia.png");
                NSView *pane = find(p.contentView, @"TabsPreferencePane") ?: find(p.contentView, @"_NSSplitViewItemViewWrapper");
                for (NSView *w in find(p.contentView, @"NSSplitView").subviews)
                    if (NSMinX(w.frame) > 0 && [NSStringFromClass(w.class) isEqualToString:@"_NSSplitViewItemViewWrapper"]) pane = w;
                dump(pane, 0, 9);
                [t selectRowIndexes:[NSIndexSet indexSetWithIndex:t.numberOfRows - 1] byExtendingSelection:NO];
                after(1.5, ^{
                    snap(p, @"/tmp/settings-daypatch.png");
                    [out writeToFile:@"/tmp/settings.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                });
            });
        });
    });
}
