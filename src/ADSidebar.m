// Adds an Arc-style URL pill below the tab sidebar header, plus back/forward/
// reload buttons in the header row next to the traffic lights. Clicking the pill
// (or ⌘L) opens Dia's own URL editor (autocomplete, history, tabs, search)
// anchored over the pill instead of the top bar.
#import "ADCommon.h"
#import <objc/runtime.h>

static NSString *const kHeaderClass = @"TabSidebar.SidebarHeaderView";
static const CGFloat kRowHeight = 40;   // pill 30 + 2 top + 8 bottom
static const CGFloat kPillHeight = 30;
static const CGFloat kSideInset = 10;
static const void *kBarKey = &kBarKey;
static const void *kNavKey = &kNavKey;
static const void *kGapKey = &kGapKey;

static void (*origLayout)(id, SEL);
static NSHashTable<NSView *> *gContainers;

static NSColor *dyn(CGFloat darkWhite, CGFloat darkAlpha, CGFloat lightWhite, CGFloat lightAlpha) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
        BOOL dark = [[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithWhite:darkWhite alpha:darkAlpha] : [NSColor colorWithWhite:lightWhite alpha:lightAlpha];
    }];
}

#pragma mark - URL pill

@interface ADSidebarURLBar : NSView
@property (nonatomic, strong) NSView *pill;
@property (nonatomic, strong) NSImageView *icon;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, copy) NSString *currentURL;
@property (nonatomic) BOOL hovering;
@end

@implementation ADSidebarURLBar

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _pill = [[NSView alloc] initWithFrame:NSZeroRect];
    _pill.wantsLayer = YES;
    _pill.layer.cornerRadius = 9;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_pill];

    _icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium];
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    [_pill addSubview:_icon];

    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    _label.textColor = NSColor.labelColor;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.placeholderString = @"Search or enter URL";
    [_pill addSubview:_label];

    [self updateAppearance];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    self.pill.frame = NSMakeRect(kSideInset, 2, NSWidth(b) - kSideInset * 2, kPillHeight);
    self.icon.frame = NSMakeRect(9, (kPillHeight - 14) / 2, 14, 14);
    CGFloat fh = 17;
    self.label.frame = NSMakeRect(27, (kPillHeight - fh) / 2, NSWidth(self.pill.frame) - 27 - 8, fh);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)e { self.hovering = YES; [self updateAppearance]; }
- (void)mouseExited:(NSEvent *)e { self.hovering = NO; [self updateAppearance]; }
- (void)mouseDown:(NSEvent *)e { [self openEditor]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateAppearance]; }

- (void)updateAppearance {
    NSColor *bg = self.hovering ? dyn(1, 0.12, 0, 0.08) : dyn(1, 0.08, 0, 0.055);
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.pill.layer.backgroundColor = bg.CGColor;
    }];
}

- (void)refresh {
    NSString *u = ADURLForWindow(self.window);
    if ([u isEqualToString:self.currentURL] && self.label.stringValue.length) return;
    self.currentURL = u;
    NSString *text = @"";
    if (u.length && ![u isEqualToString:@"about:blank"]) {
        NSString *host = [NSURL URLWithString:u].host;
        if (ADSettings.sidebarShowsFullURL || !host.length) text = u;
        else text = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
    }
    self.label.stringValue = text;
    NSString *symbol = !u.length ? @"magnifyingglass" : ([u hasPrefix:@"https://"] ? @"lock.fill" : @"globe");
    self.icon.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
}

- (void)forceRefresh { self.currentURL = nil; self.label.stringValue = @""; [self refresh]; }

- (BOOL)openEditor {
    if (ADCommandBarCurrentStyle() == ADCommandBarStyleNative) return ADCommandBarShow(self.window, NO);
    NSRect anchor = [self.pill convertRect:self.pill.bounds toView:nil];
    return ADNavBarOpenEditor(self.window, anchor);
}

@end

#pragma mark - Nav buttons

@interface ADNavButtons : NSView
@end

@implementation ADNavButtons

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NSArray *symbols = @[@"chevron.left", @"chevron.right", @"arrow.clockwise"];
    NSArray *labels = @[@"Back", @"Forward", @"Reload"];
    for (NSUInteger i = 0; i < symbols.count; i++) {
        NSButton *b = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:labels[i]]
                                         target:self action:@selector(tap:)];
        b.bordered = NO;
        b.tag = i;
        b.toolTip = labels[i];
        b.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightSemibold];
        b.contentTintColor = NSColor.secondaryLabelColor;
        [self addSubview:b];
    }
    return self;
}

- (void)layout {
    [super layout];
    CGFloat w = 26, x = 0;
    for (NSView *b in self.subviews) { b.frame = NSMakeRect(x, 0, w, NSHeight(self.bounds)); x += w; }
}

- (void)tap:(NSButton *)sender { ADNavBarPerform(self.window, sender.tag); }

@end

#pragma mark - Title observation

@interface ADTitleObserver : NSObject
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic, strong) NSHashTable<NSWindow *> *watched;
- (void)watch:(NSWindow *)w;
@end

@implementation ADTitleObserver
- (instancetype)init {
    if ((self = [super init])) _watched = [NSHashTable weakObjectsHashTable];
    return self;
}
- (void)watch:(NSWindow *)w {
    if (!w || [self.watched containsObject:w] || ![NSStringFromClass(w.class) isEqualToString:@"Window.PlatformWindow"]) return;
    [self.watched addObject:w];
    [w addObserver:self forKeyPath:@"title" options:0 context:NULL];
    __weak typeof(self) weakSelf = self;
    __unsafe_unretained NSWindow *unretained = w;
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(__unused NSNotification *n) {
        [unretained removeObserver:weakSelf forKeyPath:@"title"];
    }];
}
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    // Title often changes just before the URL settles; refresh now and once more shortly after.
    if (self.onChange) self.onChange();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (self.onChange) self.onChange(); });
}
@end

static ADTitleObserver *gTitleObserver;

#pragma mark - Container layout

static ADSidebarURLBar *barFor(NSView *container) { return objc_getAssociatedObject(container, kBarKey); }

static NSView *bodyFor(NSView *container, NSView *header) {
    for (NSView *s in container.subviews)
        if (s != header && s != barFor(container) && [NSStringFromClass(s.class) isEqualToString:@"ARCUI.FlippedView"]) return s;
    return nil;
}

static void applyContainer(NSView *c) {
    NSView *header = ADChildOfClass(c, kHeaderClass);
    NSView *body = header ? bodyFor(c, header) : nil;
    if (!header || !body || !c.isFlipped) return;

    CGFloat headerBottom = NSMaxY(header.frame);
    CGFloat H = NSHeight(c.bounds);
    // Remember the gap Dia leaves below the body (captured while unshifted).
    if (NSMinY(body.frame) == headerBottom)
        objc_setAssociatedObject(c, kGapKey, @(H - NSMaxY(body.frame)), OBJC_ASSOCIATION_RETAIN);
    CGFloat gap = [objc_getAssociatedObject(c, kGapKey) doubleValue];

    BOOL on = ADSettings.urlBarMode == ADURLBarModeSidebar && !c.isHiddenOrHasHiddenAncestor;
    ADSidebarURLBar *bar = barFor(c);
    if (on && !bar) {
        bar = [[ADSidebarURLBar alloc] initWithFrame:NSZeroRect];
        objc_setAssociatedObject(c, kBarKey, bar, OBJC_ASSOCIATION_RETAIN);
    }
    if (on && bar.superview != c) [c addSubview:bar positioned:NSWindowAbove relativeTo:header];
    if (!on) [bar removeFromSuperview];

    CGFloat top = headerBottom + (on ? kRowHeight : 0);
    NSRect bf = NSMakeRect(NSMinX(body.frame), top, NSWidth(body.frame), MAX(0, H - top - gap));
    if (!NSEqualRects(bf, body.frame)) body.frame = bf;
    if (on) {
        bar.frame = NSMakeRect(0, headerBottom, NSWidth(c.bounds), kRowHeight);
        [bar refresh];
    }

    ADNavButtons *nav = objc_getAssociatedObject(header, kNavKey);
    BOOL navOn = on && ADSettings.sidebarShowsNavButtons;
    if (navOn && !nav) {
        nav = [[ADNavButtons alloc] initWithFrame:NSZeroRect];
        objc_setAssociatedObject(header, kNavKey, nav, OBJC_ASSOCIATION_RETAIN);
    }
    if (navOn) {
        if (nav.superview != header) [header addSubview:nav];
        // Vertically centre on the traffic lights' stack.
        NSView *stack = header.subviews.firstObject;
        CGFloat mid = stack ? NSMidY(stack.frame) : NSHeight(header.bounds) / 2;
        CGFloat w = 78, h = 26;
        nav.frame = NSMakeRect(NSWidth(header.bounds) - w - 8, mid - h / 2, w, h);
    } else {
        [nav removeFromSuperview];
    }
}

static void hookedLayout(NSView *self, SEL _cmd) {
    origLayout(self, _cmd);
    [gContainers addObject:self];
    BOOL had = barFor(self).superview != nil;
    applyContainer(self);
    // The top bar's visibility depends on whether this window has a sidebar URL bar.
    // Deferred: we're inside a layout pass.
    if (had != (barFor(self).superview != nil))
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:ADSettingsDidChangeNotification object:nil];
        });
}

static ADSidebarURLBar *visibleBar(NSWindow *window) {
    for (NSView *c in gContainers.allObjects) {
        ADSidebarURLBar *bar = barFor(c);
        if (c.window == window && bar.superview && !c.isHiddenOrHasHiddenAncestor && NSWidth(c.frame) > 40) return bar;
    }
    return nil;
}

BOOL ADSidebarHasURLBar(NSWindow *window) { return visibleBar(window) != nil; }

BOOL ADSidebarFocusURLBar(NSWindow *window) { return [visibleBar(window) openEditor]; }

void ADSidebarInstall(void) {
    Class cls = ADFindClass(@"_TtC10TabSidebar", @"SidebarContainerRootView");
    if (!cls) { NSLog(@"[daypatch] SidebarContainerRootView not found; sidebar URL bar inactive"); return; }
    gContainers = [NSHashTable weakObjectsHashTable];
    origLayout = (void *)ADHook(cls, @selector(layout), (IMP)hookedLayout);
    // Refresh on navigation-ish events: Dia's window title follows the active tab's
    // page title, and switching windows/tabs changes it too. A slow timer covers
    // pages that change URL without changing title.
    void (^refreshAll)(void) = ^{ for (NSView *c in gContainers.allObjects) [barFor(c) refresh]; };
    gTitleObserver = [ADTitleObserver new];
    gTitleObserver.onChange = refreshAll;
    for (NSNotificationName n in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification, NSWindowDidUpdateNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSWindow *w = note.object;
            if (n == NSWindowDidUpdateNotification) { [gTitleObserver watch:w]; return; }
            refreshAll();
        }];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(__unused NSTimer *t) { refreshAll(); }];
    timer.tolerance = 1;
    [NSNotificationCenter.defaultCenter addObserverForName:ADSettingsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(__unused NSNotification *n) {
        for (NSView *c in gContainers.allObjects) {
            applyContainer(c);
            [barFor(c) forceRefresh];
        }
    }];
}
