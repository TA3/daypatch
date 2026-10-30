// Hides Dia's per-pane navigation bar (URL + back/forward/reload) and lets the
// web content fill the freed space. The bar can reappear as an overlay when the
// mouse touches the top edge of a pane, and stays while its URL field has focus.
#import "Common.h"

static NSString *const kPaneClass = @"ContentPane.ContentPaneView";
static NSString *const kBarClass = @"NavigationBar.NavigationBarView";
static NSString *const kContentClass = @"GesturalNavigation.GesturalNavigationEventInterceptorView";
static NSString *const kInfoBarClass = @"InfoBar.InfoBarStackView";
static const CGFloat kRevealEdge = 6;   // px from pane top that triggers reveal
static const CGFloat kKeepMargin = 12;  // extra px below bar before it hides again

static CGFloat gBarHeight = 42;
static NSHashTable<NSView *> *gPanes;
static NSMapTable<NSView *, NSNumber *> *gRevealed;
static void (*origLayout)(id, SEL);

BOOL TweakNavBarShouldHideInWindow(NSWindow *window) {
    switch (TweakSettings.urlBarMode) {
        case TweakURLBarModeTop: return NO;
        case TweakURLBarModeHidden: return YES;
        case TweakURLBarModeSidebar: return TweakSidebarHasURLBar(window);
    }
    return NO;
}

static BOOL isRevealed(NSView *pane) { return [[gRevealed objectForKey:pane] boolValue]; }

static void applyPane(NSView *pane) {
    NSView *bar = TweakChildOfClass(pane, kBarClass);
    NSView *content = TweakChildOfClass(pane, kContentClass);
    if (!bar || !content) return;
    NSRect b = pane.bounds;
    if (NSHeight(bar.frame) >= 1) gBarHeight = NSHeight(bar.frame);
    if (!TweakNavBarShouldHideInWindow(pane.window)) {
        bar.hidden = NO;
        return;
    }
    // Content fills the pane; the bar floats above it when revealed.
    NSRect cf = content.frame;
    if (NSMinY(cf) != 0 || NSHeight(cf) != NSHeight(b)) {
        cf.origin.y = 0;
        cf.size.height = NSHeight(b);
        content.frame = cf;
    }
    NSView *info = TweakChildOfClass(pane, kInfoBarClass);
    if (info && NSMinY(info.frame) == gBarHeight) {
        NSRect f = info.frame;
        f.origin.y = 0;
        info.frame = f;
    }
    BOOL show = isRevealed(pane);
    if (bar.hidden == show) bar.hidden = !show;
    // Dia collapses the bar's frame while hidden; restore it for the overlay.
    if (show && (NSHeight(bar.frame) < 1 || NSWidth(bar.frame) != NSWidth(b)))
        bar.frame = NSMakeRect(0, pane.isFlipped ? 0 : NSHeight(b) - gBarHeight, NSWidth(b), gBarHeight);
}

static void hookedLayout(NSView *self, SEL _cmd) {
    origLayout(self, _cmd);
    [gPanes addObject:self];
    applyPane(self);
}

static void (*origContentSetFrame)(id, SEL, NSRect);
static void hookedContentSetFrame(NSView *self, SEL _cmd, NSRect f) {
    NSView *pane = self.superview;
    if ([gPanes containsObject:pane] && TweakNavBarShouldHideInWindow(pane.window)) {
        f.origin.y = 0;
        f.size.height = NSHeight(pane.bounds);
    }
    origContentSetFrame(self, _cmd, f);
}

static void (*origBarSetHidden)(id, SEL, BOOL);
static void hookedBarSetHidden(NSView *self, SEL _cmd, BOOL hidden) {
    NSView *pane = self.superview;
    if (!hidden && [gPanes containsObject:pane] && TweakNavBarShouldHideInWindow(pane.window) && !isRevealed(pane)) hidden = YES;
    origBarSetHidden(self, _cmd, hidden);
}

static BOOL barHasFocus(NSView *bar) {
    id fr = bar.window.firstResponder;
    if (![fr isKindOfClass:NSView.class]) return NO;
    NSView *v = fr;
    if ([fr isKindOfClass:NSText.class] && [(NSText *)fr isFieldEditor]) {
        id d = [(NSTextView *)fr delegate];
        if ([d isKindOfClass:NSView.class]) v = d;
    }
    return [v isDescendantOf:bar];
}

static void updateReveal(void) {
    for (NSView *pane in gPanes.allObjects) {
        if (!pane.window) continue;
        NSView *bar = TweakChildOfClass(pane, kBarClass);
        if (!bar) continue;
        BOOL want = NO;
        if (TweakNavBarShouldHideInWindow(pane.window) && pane.window.isKeyWindow) {
            if (TweakSettings.revealOnHover) {
                NSPoint p = [pane convertPoint:pane.window.mouseLocationOutsideOfEventStream fromView:nil];
                BOOL inX = p.x >= 0 && p.x <= NSWidth(pane.bounds);
                CGFloat top = pane.isFlipped ? p.y : NSHeight(pane.bounds) - p.y;
                if (inX && top >= -2 && top <= kRevealEdge) want = YES;
                else if (inX && isRevealed(pane) && top >= -2 && top <= gBarHeight + kKeepMargin) want = YES;
            }
            if (barHasFocus(bar)) want = YES;
        }
        if (want != isRevealed(pane)) {
            [gRevealed setObject:@(want) forKey:pane];
            applyPane(pane);
        }
    }
}

static void relayoutAll(void) {
    for (NSView *pane in gPanes.allObjects) {
        [gRevealed setObject:@NO forKey:pane];
        if (!TweakNavBarShouldHideInWindow(pane.window)) {
            // Let Dia's own layout restore the original frames.
            TweakChildOfClass(pane, kBarClass).hidden = NO;
            [pane.superview setNeedsLayout:YES];
        }
        pane.needsLayout = YES;
    }
}

static NSView *focusedPane(NSWindow *window) {
    NSView *fallback = nil;
    id fr = window.firstResponder;
    for (NSView *pane in gPanes.allObjects) {
        if (pane.window != window || pane.isHiddenOrHasHiddenAncestor) continue;
        if ([fr isKindOfClass:NSView.class] && [(NSView *)fr isDescendantOf:pane]) return pane;
        if (!fallback) fallback = pane;
    }
    return fallback;
}

void TweakNavBarPerform(NSWindow *window, NSInteger index) {
    // Prefer Dia's own (hidden) buttons so behaviour matches the stock bar.
    NSView *bar = TweakChildOfClass(focusedPane(window), kBarClass);
    NSMutableArray<NSControl *> *controls = [NSMutableArray array];
    for (NSView *row in bar.subviews)
        for (NSView *v in row.subviews)
            if ([NSStringFromClass(v.class) containsString:@"InteractiveIconControl"] && [v isKindOfClass:NSControl.class])
                [controls addObject:(NSControl *)v];
    if (index < (NSInteger)controls.count && controls[index].action) {
        [controls[index] sendAction:controls[index].action to:controls[index].target];
        return;
    }
    if (index < 2) {
        // Walk this window's responder chain (NSApp's would use whatever window is key).
        SEL sel = NSSelectorFromString(index == 0 ? @"navigateTabBack:" : @"navigateTabForward:");
        NSView *web = TweakDescendantOfClass(focusedPane(window), @"WebContentsPaneHostView");
        for (NSResponder *r = web ?: window.firstResponder; r; r = r.nextResponder)
            if ([r respondsToSelector:sel]) { [NSApp sendAction:sel to:r from:nil]; return; }
        for (id t in @[window, (id)window.delegate ?: NSNull.null, window.windowController ?: NSNull.null, (id)NSApp.delegate ?: NSNull.null])
            if ([t respondsToSelector:sel]) { [NSApp sendAction:sel to:t from:nil]; return; }
        NSLog(@"[daypatch] no target for %@", NSStringFromSelector(sel));
    } else {
        NSString *url = TweakURLForWindow(window);
        if (url) TweakNavigateWindow(window, url);
    }
}

#pragma mark - Dia's URL editor, anchored elsewhere

// Clicking Dia's URL field opens its editor (BoostCommandBar) in a window-level
// DynamicPopover positioned over the top bar. When opened from the sidebar we
// move that popover so it grows out of the sidebar pill instead.
static __weak NSWindow *gAnchorWindow;
static NSRect gAnchorRect;   // window coordinates
static BOOL gAnchorSeen;
static NSTimeInterval gAnchorTime;
static void (*origPopoverSetFrame)(id, SEL, NSRect);
static const CGFloat kEditorWidth = 680;

static NSRect anchoredFrame(NSView *popover, NSRect proposed) {
    NSView *sv = popover.superview;
    NSRect a = [sv convertRect:gAnchorRect fromView:nil];
    CGFloat inset = 6;  // the editor's own padding around its text row
    CGFloat x = NSMinX(a) - inset;
    CGFloat w = MIN(kEditorWidth, NSWidth(sv.bounds) - x - 16);
    CGFloat h = NSHeight(proposed);
    // Drop the space of a hidden bottom toolbar (AI controls hidden by the privacy
    // module), but only while Dia's proposed height still includes it.
    NSView *toolbar = TweakDescendantOfClass(popover, @"BoostCommandBar.ToolbarView");
    NSView *root = TweakDescendantOfClass(popover, @"BoostCommandBar.RootView");
    if (toolbar.hidden && root) {
        CGFloat chrome = NSHeight(popover.frame) - NSHeight(root.frame);  // popover padding around the editor
        if (h - chrome >= NSMaxY(toolbar.frame) - 1) h -= NSHeight(toolbar.frame);
    }
    CGFloat y = sv.isFlipped ? NSMinY(a) - inset : NSMaxY(a) + inset - h;
    return NSMakeRect(x, y, MAX(w, NSWidth(a)), h);
}

static void hookedPopoverSetFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (gAnchorWindow && self.window == gAnchorWindow && self.superview) frame = anchoredFrame(self, frame);
    origPopoverSetFrame(self, _cmd, frame);
}

static Class popoverClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = TweakFindClass(@"_TtCC14DynamicPopover", @"RootView"); });
    return cls;
}

static NSView *openPopover(NSWindow *w) {
    Class cls = popoverClass();
    NSView *frame = w.contentView.superview;
    for (NSView *holder in frame.subviews)
        for (NSView *v in holder.subviews)
            if ([v isKindOfClass:cls]) return v;
    return nil;
}

static void clickView(NSView *v) {
    NSWindow *w = v.window;
    NSPoint p = [v convertPoint:NSMakePoint(NSMidX(v.bounds), NSMidY(v.bounds)) toView:nil];
    NSEventType types[] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp};
    for (int i = 0; i < 2; i++)
        [w sendEvent:[NSEvent mouseEventWithType:types[i] location:p modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1]];
}

BOOL TweakNavBarOpenEditor(NSWindow *window, NSRect anchorInWindow) {
    NSView *pane = focusedPane(window);
    NSView *bar = TweakChildOfClass(pane, kBarClass);
    if (!bar) return NO;
    // The field must be on screen to take the click: reveal the bar for a moment.
    [gRevealed setObject:@YES forKey:pane];
    applyPane(pane);
    [pane layoutSubtreeIfNeeded];
    NSView *field = TweakDescendantOfClass(bar, @"NavigationBar.AssistantBarView");
    if (!field || field.isHiddenOrHasHiddenAncestor) return NO;

    gAnchorWindow = popoverClass() ? window : nil;
    gAnchorRect = anchorInWindow;
    gAnchorSeen = NO;
    gAnchorTime = NSDate.timeIntervalSinceReferenceDate;
    clickView(field);
    [gRevealed setObject:@NO forKey:pane];
    applyPane(pane);
    NSView *pop = openPopover(window);
    if (pop && gAnchorWindow) pop.frame = pop.frame;  // re-run through the anchoring hook
    return YES;
}

void TweakNavBarInstall(void) {
    Class cls = NSClassFromString(kPaneClass);
    if (!cls) { NSLog(@"[daypatch] %@ not found; URL bar hiding inactive", kPaneClass); return; }
    gPanes = [NSHashTable weakObjectsHashTable];
    gRevealed = [NSMapTable weakToStrongObjectsMapTable];
    origLayout = (void *)TweakHook(cls, @selector(layout), (IMP)hookedLayout);
    if (popoverClass()) origPopoverSetFrame = (void *)TweakHook(popoverClass(), @selector(setFrame:), (IMP)hookedPopoverSetFrame);
    else NSLog(@"[daypatch] DynamicPopover root not found; editor opens at the top");
    // Dia moves the bar and content outside layout passes (e.g. animating back after
    // Esc in its URL editor); correct those moves as they happen.
    Class content = NSClassFromString(kContentClass);
    if (content) origContentSetFrame = (void *)TweakHook(content, @selector(setFrame:), (IMP)hookedContentSetFrame);
    Class barCls = NSClassFromString(kBarClass);
    if (barCls) origBarSetHidden = (void *)TweakHook(barCls, @selector(setHidden:), (IMP)hookedBarSetHidden);

    // Hover reveal follows the mouse; a slow timer catches the pointer leaving the
    // window and focus changes.
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved | NSEventMaskMouseExited handler:^NSEvent *(NSEvent *e) {
        if (TweakSettings.urlBarMode != TweakURLBarModeTop) updateReveal();
        return e;
    }];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) {
        if (TweakSettings.urlBarMode != TweakURLBarModeTop) updateReveal();
        // The anchor lasts for one editing session (or 2 s if the editor never opened).
        NSWindow *w = gAnchorWindow;
        if (!w) return;
        if (openPopover(w)) gAnchorSeen = YES;
        else if (gAnchorSeen || NSDate.timeIntervalSinceReferenceDate - gAnchorTime > 2) {
            gAnchorWindow = nil;
            TweakPaletteEditorClosed(w);
        }
    }];
    timer.tolerance = 0.25;
    [NSNotificationCenter.defaultCenter addObserverForName:TweakSettingsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(__unused NSNotification *n) { relayoutAll(); }];
}
