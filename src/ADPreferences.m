// Adds an "daypatch" pane to Dia's Settings window by appending a row to its
// sidebar table and swapping our own form in when that row is selected.
#import "ADCommon.h"
#import <objc/runtime.h>

static NSString *const kListClass = @"Preferences.SidebarListView";
static NSString *const kPaneTitle = @"daypatch";
static const void *kBaseCountKey = &kBaseCountKey;
static const void *kPaneKey = &kPaneKey;
static const void *kHiddenKey = &kHiddenKey;
static const void *kTitleKey = &kTitleKey;

static NSInteger (*origNumberOfRows)(id, SEL, NSTableView *);
static NSView *(*origViewForRow)(id, SEL, NSTableView *, NSTableColumn *, NSInteger);
static void (*origSelectionDidChange)(id, SEL, NSNotification *);

static NSColor *dyn(CGFloat darkWhite, CGFloat darkAlpha, CGFloat lightWhite, CGFloat lightAlpha) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
        BOOL dark = [[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithWhite:darkWhite alpha:darkAlpha] : [NSColor colorWithWhite:lightWhite alpha:lightAlpha];
    }];
}

#pragma mark - Pane UI

@interface ADGroupView : NSView
@end

@implementation ADGroupView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.backgroundColor = dyn(1, 0.05, 0, 0.035).CGColor;
    self.layer.borderWidth = 1;
    self.layer.borderColor = dyn(1, 0.06, 0, 0.06).CGColor;
}
@end

@interface ADFlippedView : NSView
@end

@implementation ADFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface ADPrefsPane : NSView
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) NSTextField *blockedLabel;
@property (nonatomic, strong) NSPopUpButton *rendererPopup;
@property (nonatomic, strong) NSPopUpButton *commandBarPopup;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSSwitch *> *switches;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSView *> *> *rowsByKey;
@end

@implementation ADPrefsPane

- (BOOL)isFlipped { return YES; }

- (NSTextField *)label:(NSString *)s size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *t = [NSTextField wrappingLabelWithString:s];
    t.font = [NSFont systemFontOfSize:size weight:weight];
    t.textColor = color;
    t.selectable = NO;
    return t;
}

- (NSView *)rowWithTitle:(NSString *)title detail:(NSString *)detail control:(NSView *)control key:(NSString *)key {
    NSStackView *texts = [NSStackView stackViewWithViews:@[[self label:title size:13 weight:NSFontWeightRegular color:NSColor.labelColor]]];
    texts.orientation = NSUserInterfaceLayoutOrientationVertical;
    texts.alignment = NSLayoutAttributeLeading;
    texts.spacing = 3;
    if (detail) [texts addArrangedSubview:[self label:detail size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor]];
    [texts setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [texts setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *row = [NSStackView stackViewWithViews:@[texts, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 20;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (key) self.rowsByKey[key] = @[texts, control];

    // Explicit padding (stack edge insets aren't honoured for wrapping labels).
    // Matches Dia's grouped settings: 12 pt above/below, 14 pt at the sides.
    NSView *cell = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:cell.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-14],
        [cell.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return cell;
}

- (NSView *)groupWithRows:(NSArray<NSView *> *)rows {
    ADGroupView *g = [[ADGroupView alloc] initWithFrame:NSZeroRect];
    g.wantsLayer = YES;
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i) {
            NSBox *sep = [[NSBox alloc] initWithFrame:NSZeroRect];
            sep.boxType = NSBoxSeparator;
            [items addObject:sep];
        }
        [items addObject:rows[i]];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:items];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeWidth;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [g addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
    ]];
    for (NSView *sep in items)
        if ([sep isKindOfClass:NSBox.class])
            [sep.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:14].active = YES;
    return g;
}

- (NSSwitch *)switchForKey:(NSString *)key {
    NSSwitch *s = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    s.controlSize = NSControlSizeSmall;
    s.target = self;
    s.action = @selector(switchChanged:);
    s.identifier = key;
    self.switches[key] = s;
    return s;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _switches = [NSMutableDictionary dictionary];
    _rowsByKey = [NSMutableDictionary dictionary];

    _modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSArray *m in @[@[@"Top (Dia default)", @(ADURLBarModeTop)], @[@"Hidden", @(ADURLBarModeHidden)], @[@"In sidebar", @(ADURLBarModeSidebar)]]) {
        [_modePopup addItemWithTitle:m[0]];
        _modePopup.lastItem.tag = [m[1] integerValue];
    }
    _modePopup.target = self;
    _modePopup.action = @selector(modeChanged:);

    _commandBarPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSArray *m in @[@[@"daypatch (Arc-style)", @(ADCommandBarStyleNative)], @[@"Dia's editor", @(ADCommandBarStyleDiaEditor)], @[@"Off (Dia default)", @(ADCommandBarStyleOff)]]) {
        [_commandBarPopup addItemWithTitle:m[0]];
        _commandBarPopup.lastItem.tag = [m[1] integerValue];
    }
    _commandBarPopup.target = self;
    _commandBarPopup.action = @selector(commandBarChanged:);

    NSView *urlGroup = [self groupWithRows:@[
        [self rowWithTitle:@"URL bar position" detail:@"Where the address and back, forward and reload controls live." control:_modePopup key:nil],
        [self rowWithTitle:@"Command bar" detail:@"What ⌘T, ⌘L and the sidebar URL bar open. daypatch's bar finds tabs, history, bookmarks and commands." control:_commandBarPopup key:nil],
        [self rowWithTitle:@"Reveal top bar on hover" detail:@"Move the pointer to the top edge of a page to show Dia's bar." control:[self switchForKey:ADKeyRevealOnHover] key:ADKeyRevealOnHover],
    ]];
    NSView *sidebarGroup = [self groupWithRows:@[
        [self rowWithTitle:@"⌘L opens the sidebar URL bar" detail:@"With Dia's editor as the command bar: open it at the sidebar instead of the top." control:[self switchForKey:ADKeyCmdLFocusesSidebar] key:ADKeyCmdLFocusesSidebar],
        [self rowWithTitle:@"Show full URL" detail:@"Otherwise only the site's domain is shown." control:[self switchForKey:ADKeySidebarFullURL] key:ADKeySidebarFullURL],
        [self rowWithTitle:@"Back, forward and reload buttons" detail:@"Shown next to the window controls." control:[self switchForKey:ADKeySidebarNavButtons] key:ADKeySidebarNavButtons],
    ]];
    NSView *privacyGroup = [self groupWithRows:@[
        [self rowWithTitle:@"Hide AI features" detail:@"Chat menus and shortcuts, Chats in the sidebar, the Chat button, \u201cAdd tabs or files\u201d, and page content extraction." control:[self switchForKey:ADKeyHideAI] key:ADKeyHideAI],
        [self rowWithTitle:@"Block AI services" detail:@"Dia's AI endpoints (chat, AI search, artifacts) and Google's Gemini API. Hover for the full list." control:[self switchForKey:ADKeyBlockAI] key:ADKeyBlockAI],
        [self rowWithTitle:@"Block telemetry" detail:@"Datadog, Sentry, Segment, LaunchDarkly events and Dia's OpenTelemetry gateway." control:[self switchForKey:ADKeyBlockTelemetry] key:ADKeyBlockTelemetry],
    ]];
    _blockedLabel = [self label:@"" size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.rowsByKey[ADKeyBlockAI].firstObject.toolTip = [@"Blocked hosts:\n" stringByAppendingString:[ADAIHosts() componentsJoinedByString:@"\n"]];

    _rendererPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSArray *r in @[@[@"Chromium default", @0], @[@"16", @16], @[@"8", @8], @[@"4", @4]]) {
        [_rendererPopup addItemWithTitle:r[0]];
        _rendererPopup.lastItem.tag = [r[1] integerValue];
    }
    _rendererPopup.target = self;
    _rendererPopup.action = @selector(rendererChanged:);
    NSView *perfGroup = [self groupWithRows:@[
        [self rowWithTitle:@"Turn off on-device AI" detail:@"Don't start Dia's local AI service process (about 40 MB), which otherwise classifies everything typed in the URL editor. Requires Hide AI features." control:[self switchForKey:ADKeyDisableOnDeviceAI] key:ADKeyDisableOnDeviceAI],
        [self rowWithTitle:@"Renderer process limit" detail:@"Tabs share processes above this number: less memory with many tabs, but one crash can take several tabs with it." control:_rendererPopup key:ADKeyRendererLimit],
        [self rowWithTitle:@"Disable background networking" detail:@"Stops Chromium's background updaters (components, field trials). May delay Safe Browsing list updates." control:[self switchForKey:ADKeyNoBackgroundNetworking] key:ADKeyNoBackgroundNetworking],
    ]];
    NSTextField *perfNote = [self label:@"Performance options apply after restarting Patched Dia." size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];

    NSTextField *footer = [self label:@"Press ⌃⌘U to switch between Dia's URL bar and the option above.\ndaypatch is an unofficial patch. Rebuild it after each Dia update."
                                 size:11 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        [self label:@"URL bar" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor], urlGroup,
        [self label:@"Sidebar URL bar" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor], sidebarGroup,
        [self label:@"Privacy" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor], privacyGroup, _blockedLabel,
        [self label:@"Performance" size:13 weight:NSFontWeightSemibold color:NSColor.labelColor], perfGroup, perfNote,
        footer,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    [stack setCustomSpacing:20 afterView:urlGroup];
    [stack setCustomSpacing:20 afterView:sidebarGroup];
    [stack setCustomSpacing:20 afterView:_blockedLabel];
    [stack setCustomSpacing:14 afterView:perfNote];
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.automaticallyAdjustsContentInsets = YES;  // clears the transparent titlebar
    ADFlippedView *doc = [[ADFlippedView alloc] initWithFrame:NSZeroRect];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = doc;
    [self addSubview:scroll];
    [doc addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [doc.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [stack.topAnchor constraintEqualToAnchor:doc.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-20],
        [urlGroup.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [sidebarGroup.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [privacyGroup.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [perfGroup.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [footer.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    [self sync];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *t) { [weakSelf updateBlocked]; }];
    _timer.tolerance = 0.5;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:ADSettingsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc { [_timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)updateBlocked {
    self.blockedLabel.stringValue = [NSString stringWithFormat:@"%lu requests blocked since launch. Blocking changes fully apply after restarting Patched Dia.",
                                     (unsigned long)ADBlockedRequestCount()];
}

- (void)setRow:(NSString *)key enabled:(BOOL)on {
    for (NSView *v in self.rowsByKey[key]) {
        v.alphaValue = on ? 1 : 0.45;
        if ([v isKindOfClass:NSControl.class]) [(NSControl *)v setEnabled:on];
    }
}

- (void)sync {
    ADURLBarMode mode = ADSettings.urlBarMode;
    [self.modePopup selectItemWithTag:mode];
    [self.commandBarPopup selectItemWithTag:ADCommandBarCurrentStyle()];
    [self.rendererPopup selectItemWithTag:[NSUserDefaults.standardUserDefaults integerForKey:ADKeyRendererLimit]];
    [self setRow:ADKeyDisableOnDeviceAI enabled:[ADSettings boolForKey:ADKeyHideAI]];
    for (NSString *key in self.switches) self.switches[key].state = [ADSettings boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
    [self setRow:ADKeyRevealOnHover enabled:mode != ADURLBarModeTop];
    for (NSString *k in @[ADKeyCmdLFocusesSidebar, ADKeySidebarFullURL, ADKeySidebarNavButtons])
        [self setRow:k enabled:mode == ADURLBarModeSidebar];
}

- (void)modeChanged:(NSPopUpButton *)p { [ADSettings setURLBarMode:p.selectedTag]; }
- (void)commandBarChanged:(NSPopUpButton *)p {
    [NSUserDefaults.standardUserDefaults setInteger:p.selectedTag forKey:ADKeyCommandBarStyle];
    [NSNotificationCenter.defaultCenter postNotificationName:ADSettingsDidChangeNotification object:nil];
}
- (void)rendererChanged:(NSPopUpButton *)p {
    [NSUserDefaults.standardUserDefaults setInteger:p.selectedTag forKey:ADKeyRendererLimit];
    [NSNotificationCenter.defaultCenter postNotificationName:ADSettingsDidChangeNotification object:nil];
}
- (void)switchChanged:(NSSwitch *)s { [ADSettings setBool:s.state == NSControlStateValueOn forKey:s.identifier]; }

@end

#pragma mark - Settings window plumbing

static NSInteger baseCount(NSTableView *t) { return [objc_getAssociatedObject(t, kBaseCountKey) integerValue]; }

static NSView *paneHost(NSWindow *w) {
    // The detail side of the settings split view (the item that isn't at x = 0).
    NSMutableArray *queue = [NSMutableArray arrayWithObject:w.contentView];
    while (queue.count) {
        NSView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:NSSplitView.class]) {
            for (NSView *item in v.subviews)
                if (NSMinX(item.frame) > 0 && NSWidth(item.frame) > 100 && item.subviews.count) return item.subviews.firstObject;
            return nil;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

static NSTextField *titleField(NSWindow *w) {
    for (NSToolbarItem *item in w.toolbar.items) {
        if (![item.itemIdentifier isEqualToString:@"PreferencesPaneTitle"]) continue;
        NSMutableArray *queue = item.view ? [NSMutableArray arrayWithObject:item.view] : [NSMutableArray array];
        while (queue.count) {
            NSView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([v isKindOfClass:NSTextField.class]) return (NSTextField *)v;
            [queue addObjectsFromArray:v.subviews];
        }
    }
    return nil;
}

static void showPane(NSWindow *w, BOOL show) {
    NSView *host = paneHost(w);
    if (!host) return;
    ADPrefsPane *pane = objc_getAssociatedObject(w, kPaneKey);
    NSTextField *title = titleField(w);
    if (show) {
        if (!pane) {
            pane = [[ADPrefsPane alloc] initWithFrame:host.bounds];
            pane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            objc_setAssociatedObject(w, kPaneKey, pane, OBJC_ASSOCIATION_RETAIN);
        }
        if (pane.superview == host) return;
        NSMutableArray *hidden = [NSMutableArray array];
        for (NSView *v in host.subviews)
            if (!v.hidden) { v.hidden = YES; [hidden addObject:v]; }
        objc_setAssociatedObject(w, kHiddenKey, hidden, OBJC_ASSOCIATION_RETAIN);
        pane.frame = host.bounds;
        [host addSubview:pane];
        if (title) {
            objc_setAssociatedObject(w, kTitleKey, title.stringValue, OBJC_ASSOCIATION_RETAIN);
            title.stringValue = kPaneTitle;
        }
    } else if (pane.superview) {
        [pane removeFromSuperview];
        for (NSView *v in objc_getAssociatedObject(w, kHiddenKey)) v.hidden = NO;
        objc_setAssociatedObject(w, kHiddenKey, nil, OBJC_ASSOCIATION_RETAIN);
        NSString *old = objc_getAssociatedObject(w, kTitleKey);
        if (title && old && [title.stringValue isEqualToString:kPaneTitle]) title.stringValue = old;
    }
}

static NSInteger hookedNumberOfRows(id self, SEL _cmd, NSTableView *t) {
    NSInteger n = origNumberOfRows(self, _cmd, t);
    objc_setAssociatedObject(t, kBaseCountKey, @(n), OBJC_ASSOCIATION_RETAIN);
    return n + 1;
}

static NSView *makeCell(NSTableView *t) {
    // Match Dia's own cells: 18pt icon at x=5, label at x=32.
    NSFont *font = [NSFont systemFontOfSize:13];
    NSView *sample = [t viewAtColumn:0 row:0 makeIfNecessary:NO];
    for (NSView *v in sample.subviews)
        if ([v isKindOfClass:NSTextField.class]) font = [(NSTextField *)v font];

    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 164, 28)];
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"sidebar.left" accessibilityDescription:kPaneTitle]];
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
    icon.contentTintColor = NSColor.labelColor;
    icon.frame = NSMakeRect(5, 2, 18, 24);
    NSTextField *label = [NSTextField labelWithString:kPaneTitle];
    label.font = font;
    label.frame = NSMakeRect(32, 6, 120, 17);
    [cell addSubview:icon];
    [cell addSubview:label];
    cell.imageView = icon;
    cell.textField = label;
    return cell;
}

static NSView *hookedViewForRow(id self, SEL _cmd, NSTableView *t, NSTableColumn *col, NSInteger row) {
    if (row == baseCount(t)) return makeCell(t);
    return origViewForRow(self, _cmd, t, col, row);
}

static void hookedSelectionDidChange(id self, SEL _cmd, NSNotification *n) {
    NSTableView *t = n.object;
    if ([t isKindOfClass:NSTableView.class] && t.selectedRow == baseCount(t)) {
        showPane(t.window, YES);
        return;  // Dia's handler would index past its own pane list.
    }
    if ([t isKindOfClass:NSTableView.class]) showPane(t.window, NO);
    origSelectionDidChange(self, _cmd, n);
}

void ADPreferencesInstall(void) {
    Class cls = NSClassFromString(kListClass);
    if (!cls) { NSLog(@"[daypatch] %@ not found; settings pane inactive", kListClass); return; }
    origNumberOfRows = (void *)ADHook(cls, @selector(numberOfRowsInTableView:), (IMP)hookedNumberOfRows);
    origViewForRow = (void *)ADHook(cls, @selector(tableView:viewForTableColumn:row:), (IMP)hookedViewForRow);
    origSelectionDidChange = (void *)ADHook(cls, @selector(tableViewSelectionDidChange:), (IMP)hookedSelectionDidChange);
    if (!origNumberOfRows || !origViewForRow || !origSelectionDidChange)
        NSLog(@"[daypatch] settings hooks incomplete");
}
