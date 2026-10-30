// Dev tool: triggers a sidebar tab's hover card and lists its action buttons
// (class, tooltip, hidden). Output: /tmp/daypatch-hovercard.txt.
#import <AppKit/AppKit.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }
static void collect(NSView *v, NSString *needle, NSMutableArray *acc) {
    if ([NSStringFromClass(v.class) containsString:needle]) [acc addObject:v];
    for (NSView *s in v.subviews) collect(s, needle, acc);
}

static void listButtons(NSString *label) {
    [out appendFormat:@"-- %@\n", label];
    for (NSWindow *w in NSApp.windows) {
        NSMutableArray *found = [NSMutableArray array];
        collect(w.contentView.superview ?: w.contentView, @"TabPopoverActionButton", found);
        for (NSView *b in found)
            [out appendFormat:@"   %@ in %@: tooltip=\"%@\" ax=\"%@\" hidden=%d\n", NSStringFromClass(b.class), NSStringFromClass(w.class), b.toolTip, b.accessibilityLabel, b.isHiddenOrHasHiddenAncestor];
    }
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(9, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES]; [w makeKeyAndOrderFront:nil];
        NSMutableArray *cells = [NSMutableArray array];
        collect(w.contentView.superview, @"TabCellHostingRootView", cells);
        NSView *cell = cells.count > 1 ? cells[1] : cells.firstObject;
        [out appendFormat:@"cells=%lu target=%@\n", (unsigned long)cells.count, NSStringFromClass(cell.class)];
        NSPoint p = [cell convertPoint:NSMakePoint(NSMidX(cell.bounds), NSMidY(cell.bounds)) toView:nil];
        // Hover: tracking-area owners get mouseEntered/mouseMoved.
        for (NSTrackingArea *t in cell.trackingAreas) {
            NSEvent *e = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:p modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                            windowNumber:w.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:(__bridge void *)t.userInfo];
            [t.owner mouseEntered:e];
        }
        [w sendEvent:[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:p modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0]];
        after(2.5, ^{
            listButtons(@"after hover");
            [out writeToFile:@"/tmp/daypatch-hovercard.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
    });
}
