// daypatch's own command bar: an Arc-style palette over the window that finds
// open tabs, history, bookmarks, Dia's menu commands, chrome:// pages, or searches.
//   ⌘T          new-tab mode (results open in a new tab)
//   ⌘L / pill   current-tab mode, pre-filled with the current URL
#import "ADCommon.h"
#import "ADCommandSources.h"

typedef NS_ENUM(NSInteger, ADCommandBarMode) { ADCommandBarNewTab, ADCommandBarCurrentTab };

static const CGFloat kWidth = 760;
static const CGFloat kInputHeight = 64;
static const CGFloat kRowHeight = 44;
static const CGFloat kListInset = 8;
static const NSUInteger kMaxRows = 8;

static NSColor *dyn(CGFloat dw, CGFloat da, CGFloat lw, CGFloat la) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
        BOOL dark = [[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithWhite:dw alpha:da] : [NSColor colorWithWhite:lw alpha:la];
    }];
}

#pragma mark - Results list

@class ADResultsView;
@protocol ADResultsViewDelegate
- (void)resultsView:(ADResultsView *)v activate:(NSInteger)row;
- (NSImage *)iconForItem:(ADItem *)item;
@end

@interface ADResultsView : NSView
@property (nonatomic, copy) NSArray<ADItem *> *items;
@property (nonatomic) NSInteger selected;
@property (nonatomic, weak) id<ADResultsViewDelegate> delegate;
@end

@implementation ADResultsView

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }

- (void)setItems:(NSArray<ADItem *> *)items { _items = [items copy]; _selected = items.count ? 0 : -1; self.needsDisplay = YES; }
- (void)setSelected:(NSInteger)s { _selected = s; self.needsDisplay = YES; }

- (NSRect)rectForRow:(NSInteger)r {
    return NSMakeRect(kListInset, kListInset + r * kRowHeight, NSWidth(self.bounds) - kListInset * 2, kRowHeight);
}

- (NSInteger)rowAt:(NSPoint)p {
    for (NSInteger r = 0; r < (NSInteger)self.items.count; r++) if (NSPointInRect(p, [self rectForRow:r])) return r;
    return -1;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseMoved:(NSEvent *)e {
    NSInteger r = [self rowAt:[self convertPoint:e.locationInWindow fromView:nil]];
    if (r >= 0 && r != self.selected) self.selected = r;
}

- (void)mouseDown:(NSEvent *)e {
    NSInteger r = [self rowAt:[self convertPoint:e.locationInWindow fromView:nil]];
    if (r >= 0) [self.delegate resultsView:self activate:r];
}

- (void)drawRect:(NSRect)dirty {
    NSFont *titleFont = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    NSFont *detailFont = [NSFont systemFontOfSize:15 weight:NSFontWeightRegular];
    NSMutableParagraphStyle *trunc = [NSMutableParagraphStyle new];
    trunc.lineBreakMode = NSLineBreakByTruncatingMiddle;
    for (NSInteger r = 0; r < (NSInteger)self.items.count; r++) {
        ADItem *it = self.items[r];
        NSRect row = [self rectForRow:r];
        if (r == self.selected) {
            [dyn(1, 0.10, 0, 0.07) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:10 yRadius:10] fill];
        }

        // Icon: favicon, or a symbol (commands get a filled tile, like Arc).
        NSRect iconRect = NSMakeRect(NSMinX(row) + 14, NSMidY(row) - 10, 20, 20);
        NSImage *icon = [self.delegate iconForItem:it];
        if (it.kind == ADItemCommand || it.kind == ADItemPage) {
            NSRect tile = NSInsetRect(iconRect, -4, -4);
            [(it.kind == ADItemCommand ? NSColor.labelColor : dyn(1, 0.14, 0, 0.08)) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:tile xRadius:7 yRadius:7] fill];
            NSImage *sym = [[NSImage imageWithSystemSymbolName:it.symbol accessibilityDescription:nil]
                            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
            NSColor *tint = it.kind == ADItemCommand ? NSColor.windowBackgroundColor : NSColor.labelColor;
            [self drawSymbol:sym in:iconRect tint:tint];
        } else if (icon) {
            if (r == self.selected) {
                // Selected favicons sit on a white tile, like Arc.
                [NSColor.whiteColor setFill];
                [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(iconRect, -4, -4) xRadius:7 yRadius:7] fill];
            }
            [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        } else {
            NSImage *sym = [[NSImage imageWithSystemSymbolName:it.symbol accessibilityDescription:nil]
                            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]];
            [self drawSymbol:sym in:iconRect tint:NSColor.secondaryLabelColor];
        }

        // Title — detail, with the detail truncated first.
        CGFloat x = NSMaxX(iconRect) + 16, maxX = NSMaxX(row) - 16;
        NSString *right = it.kind == ADItemCommand ? it.detail : nil;
        if (it.kind == ADItemTab) {
            // "Switch to Tab" + arrow chip; bright when selected.
            BOOL sel = r == self.selected;
            NSRect chip = NSMakeRect(maxX - 28 + 4, NSMidY(row) - 14, 28, 28);
            [(sel ? NSColor.labelColor : dyn(1, 0.08, 0, 0.06)) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:chip xRadius:7 yRadius:7] fill];
            NSImage *arrow = [[NSImage imageWithSystemSymbolName:@"arrow.right" accessibilityDescription:@"Switch to Tab"]
                              imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightSemibold]];
            [self drawSymbol:arrow in:chip tint:sel ? NSColor.windowBackgroundColor : NSColor.secondaryLabelColor];
            NSDictionary *ra = @{NSFontAttributeName: sel ? titleFont : detailFont,
                                 NSForegroundColorAttributeName: sel ? NSColor.labelColor : NSColor.tertiaryLabelColor};
            NSSize rs = [it.detail sizeWithAttributes:ra];
            [it.detail drawAtPoint:NSMakePoint(NSMinX(chip) - 12 - rs.width, NSMidY(row) - rs.height / 2) withAttributes:ra];
            maxX = NSMinX(chip) - 12 - rs.width - 16;
        }
        if (right.length) {
            NSDictionary *ra = @{NSFontAttributeName: detailFont, NSForegroundColorAttributeName: NSColor.tertiaryLabelColor};
            NSSize rs = [right sizeWithAttributes:ra];
            [right drawAtPoint:NSMakePoint(maxX - rs.width, NSMidY(row) - rs.height / 2) withAttributes:ra];
            maxX -= rs.width + 16;
        }
        NSDictionary *ta = @{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: trunc};
        NSString *title = it.title ?: @"";
        NSSize ts = [title sizeWithAttributes:ta];
        CGFloat titleW = MIN(ts.width, (maxX - x) * 0.6);
        if (!(it.kind == ADItemHistory || it.kind == ADItemBookmark || it.kind == ADItemPage || it.kind == ADItemSearch || it.kind == ADItemURL)) titleW = MIN(ts.width, maxX - x);
        [title drawInRect:NSMakeRect(x, NSMidY(row) - ts.height / 2, titleW, ts.height) withAttributes:ta];
        NSString *detail = nil;
        if (it.kind == ADItemHistory || it.kind == ADItemBookmark || it.kind == ADItemPage) detail = [self prettyURL:it.url];
        else if (it.kind == ADItemSearch || it.kind == ADItemURL) detail = it.detail;
        if (detail.length) {
            NSDictionary *da = @{NSFontAttributeName: detailFont, NSForegroundColorAttributeName: NSColor.tertiaryLabelColor, NSParagraphStyleAttributeName: trunc};
            NSString *d = [@"— " stringByAppendingString:detail];
            NSSize ds = [d sizeWithAttributes:da];
            CGFloat dx = x + titleW + 8;
            [d drawInRect:NSMakeRect(dx, NSMidY(row) - ds.height / 2, MAX(0, maxX - dx), ds.height) withAttributes:da];
        }
    }
}

- (void)drawSymbol:(NSImage *)sym in:(NSRect)r tint:(NSColor *)tint {
    if (!sym) return;
    NSImage *tinted = [NSImage imageWithSize:sym.size flipped:NO drawingHandler:^BOOL(NSRect dst) {
        [sym drawInRect:dst];
        [tint set];
        NSRectFillUsingOperation(dst, NSCompositingOperationSourceAtop);
        return YES;
    }];
    NSSize s = sym.size;
    NSRect fit = NSMakeRect(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2, s.width, s.height);
    [tinted drawInRect:fit fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

- (NSString *)prettyURL:(NSString *)u {
    NSString *s = u;
    for (NSString *p in @[@"https://", @"http://"]) if ([s hasPrefix:p]) s = [s substringFromIndex:p.length];
    if ([s hasPrefix:@"www."]) s = [s substringFromIndex:4];
    if ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

@end

#pragma mark - Panel

@interface ADCommandPanel : NSPanel
@end

@implementation ADCommandPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface ADCommandBar : NSObject <NSTextFieldDelegate, NSWindowDelegate, ADResultsViewDelegate>
@property (nonatomic, strong) ADCommandPanel *panel;
@property (nonatomic, strong) NSVisualEffectView *background;
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSImageView *fieldIcon;
@property (nonatomic, strong) NSBox *divider;
@property (nonatomic, strong) ADResultsView *results;
@property (nonatomic, strong) ADCommandSources *sources;
@property (nonatomic, weak) NSWindow *host;
@property (nonatomic) ADCommandBarMode mode;
@property (nonatomic, copy) NSString *typed;       // what the user typed (without inline completion)
@property (nonatomic) BOOL suppressCompletion;     // after a deletion
@end

@implementation ADCommandBar

+ (instancetype)shared {
    static ADCommandBar *bar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bar = [ADCommandBar new]; });
    return bar;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _sources = [ADCommandSources new];

    _panel = [[ADCommandPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, kInputHeight)
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView
                                                 backing:NSBackingStoreBuffered defer:YES];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.level = NSFloatingWindowLevel;
    _panel.delegate = self;
    _panel.releasedWhenClosed = NO;
    _panel.hidesOnDeactivate = YES;

    _background = [[NSVisualEffectView alloc] initWithFrame:_panel.contentView.bounds];
    _background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _background.material = NSVisualEffectMaterialHUDWindow;
    _background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _background.state = NSVisualEffectStateActive;
    _background.wantsLayer = YES;
    _background.layer.cornerRadius = 16;
    _background.layer.cornerCurve = kCACornerCurveContinuous;
    _background.layer.masksToBounds = YES;
    _background.layer.borderWidth = 1;
    _panel.contentView = _background;

    _fieldIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _fieldIcon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular];
    _fieldIcon.contentTintColor = NSColor.secondaryLabelColor;
    [_background addSubview:_fieldIcon];

    _field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:22 weight:NSFontWeightMedium];
    _field.placeholderString = @"Search or enter URL";
    _field.cell.scrollable = YES;
    _field.cell.wraps = NO;
    _field.delegate = self;
    [_background addSubview:_field];

    _divider = [[NSBox alloc] initWithFrame:NSZeroRect];
    _divider.boxType = NSBoxSeparator;
    [_background addSubview:_divider];

    _results = [[ADResultsView alloc] initWithFrame:NSZeroRect];
    _results.delegate = self;
    [_background addSubview:_results];
    return self;
}

#pragma mark Showing

- (void)showInWindow:(NSWindow *)window mode:(ADCommandBarMode)mode {
    if (!window) return;
    if (self.panel.isVisible) [self close];
    self.host = window;
    self.mode = mode;
    self.panel.appearance = window.effectiveAppearance;
    [self.background.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.background.layer.borderColor = dyn(1, 0.12, 0, 0.10).CGColor;
    }];
    [self.sources prepareForWindow:window];

    NSString *initial = @"";
    if (mode == ADCommandBarCurrentTab) {
        NSString *u = ADURLForWindow(window);
        if (u.length && ![u hasPrefix:@"dia://"]) initial = u;
    }
    self.field.stringValue = initial;
    self.typed = initial;
    [self layoutForRows:0];
    [window addChildWindow:self.panel ordered:NSWindowAbove];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.field];
    [self.field.currentEditor selectAll:nil];
    // Current-tab mode starts with the URL selected and no list (like Arc's ⌘L).
    if (mode == ADCommandBarNewTab) [self runQuery];
    else [self showItems:@[]];
}

- (void)layoutForRows:(NSUInteger)rows {
    NSWindow *w = self.host;
    NSRect wf = w.frame;
    CGFloat width = MIN(kWidth, NSWidth(wf) - 80);
    CGFloat listH = rows ? rows * kRowHeight + kListInset * 2 : 0;
    CGFloat height = kInputHeight + (rows ? 1 + listH : 0);
    CGFloat top = NSMaxY(wf) - NSHeight(wf) * 0.20;  // about a fifth of the way down
    [self.panel setFrame:NSMakeRect(NSMidX(wf) - width / 2, top - height, width, height) display:YES];

    self.fieldIcon.frame = NSMakeRect(22, height - kInputHeight / 2 - 12, 24, 24);
    self.field.frame = NSMakeRect(58, height - kInputHeight / 2 - 15, width - 58 - 22, 30);
    self.divider.hidden = rows == 0;
    self.divider.frame = NSMakeRect(0, height - kInputHeight - 1, width, 1);
    self.results.frame = NSMakeRect(0, 0, width, listH);
}

- (void)close {
    [self.host removeChildWindow:self.panel];
    [self.panel orderOut:nil];
    [self.host makeKeyAndOrderFront:nil];
}

- (void)windowDidResignKey:(NSNotification *)n {
    // Clicking outside closes it, like Arc.
    if (self.panel.isVisible) [self close];
}

#pragma mark Querying

- (void)runQuery {
    NSString *q = self.typed ?: @"";
    __weak typeof(self) weakSelf = self;
    [self.sources query:q done:^(NSArray<ADItem *> *items) {
        typeof(self) s = weakSelf;
        if (![s.typed isEqualToString:q]) return;
        [s showItems:items];
        [s applyCompletionFrom:items];
    }];
}

- (void)showItems:(NSArray<ADItem *> *)items {
    self.results.items = items;
    [self layoutForRows:MIN(kMaxRows, items.count)];
    [self updateFieldIcon];
}

- (void)updateFieldIcon {
    ADItem *top = self.results.selected >= 0 ? self.results.items[self.results.selected] : nil;
    NSImage *img = top ? [self iconForItem:top] : nil;
    if (!img || top.kind == ADItemCommand || top.kind == ADItemPage)
        img = [NSImage imageWithSystemSymbolName:top ? top.symbol : @"magnifyingglass" accessibilityDescription:nil];
    self.fieldIcon.image = img;
}

// Inline completion: "git" -> "git|hub.com" with the suffix selected.
- (void)applyCompletionFrom:(NSArray<ADItem *> *)items {
    if (self.suppressCompletion) return;
    NSString *host = [self.sources completionFor:self.typed inItems:items];
    NSText *editor = self.field.currentEditor;
    if (!host || !editor || ![editor.string isEqualToString:self.typed]) return;
    NSString *suffix = [host substringFromIndex:self.typed.length];
    editor.string = [self.typed stringByAppendingString:suffix];
    editor.selectedRange = NSMakeRange(self.typed.length, suffix.length);
}

- (void)controlTextDidChange:(NSNotification *)n {
    NSString *now = self.field.stringValue;
    // Deleting shouldn't immediately re-complete what was just removed.
    self.suppressCompletion = now.length < self.typed.length && [self.typed hasPrefix:now];
    self.typed = now;
    [self runQuery];
}

- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    NSInteger n = self.results.items.count;
    if (sel == @selector(moveDown:) || sel == @selector(moveUp:)) {
        if (!n) return YES;
        NSInteger s = self.results.selected + (sel == @selector(moveDown:) ? 1 : -1);
        self.results.selected = (s + n) % n;
        [self updateFieldIcon];
        return YES;
    }
    if (sel == @selector(insertTab:)) {  // accept the inline completion
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        self.typed = tv.string;
        [self runQuery];
        return YES;
    }
    if (sel == @selector(insertNewline:)) {
        BOOL newTab = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagCommand) != 0;
        // An inline completion is showing and the top row is still selected: go to it.
        BOOL completed = ![tv.string isEqualToString:self.typed] && self.results.selected == 0;
        [self activateRow:completed ? -1 : self.results.selected forceNewTab:newTab];
        return YES;
    }
    if (sel == @selector(cancelOperation:)) { [self close]; return YES; }
    return NO;
}

#pragma mark Activation

- (void)resultsView:(ADResultsView *)v activate:(NSInteger)row { [self activateRow:row forceNewTab:NO]; }

- (void)activateRow:(NSInteger)row forceNewTab:(BOOL)forceNewTab {
    NSWindow *w = self.host;
    ADItem *it = row >= 0 && row < (NSInteger)self.results.items.count ? self.results.items[row] : nil;
    NSString *typedText = self.field.stringValue;
    [self close];
    if (!it) {
        // Nothing listed (e.g. ⌘L with the URL untouched): treat the field as an address/search.
        if (!typedText.length) return;
        it = [ADItem new];
        it.kind = ADItemURL;
        it.url = ADResolveInput(typedText);
    }
    switch (it.kind) {
        case ADItemCommand: {
            NSMenuItem *m = it.menuItem;
            dispatch_async(dispatch_get_main_queue(), ^{ [NSApp sendAction:m.action to:m.target from:m]; });
            break;
        }
        case ADItemTab:
            ADFocusTab(it.windowId, it.tabId);
            break;
        default: {
            NSString *url = it.url;
            // The URL row reflects what's in the field, including an accepted completion.
            if (it.kind == ADItemURL && ![typedText isEqualToString:it.title]) url = ADResolveInput(typedText);
            if (!url) return;
            if (self.mode == ADCommandBarNewTab || forceNewTab) ADOpenInNewTab(w, url);
            else ADNavigateWindow(w, url);
        }
    }
}

- (NSImage *)iconForItem:(ADItem *)item {
    if (item.kind == ADItemCommand || item.kind == ADItemPage || item.kind == ADItemSearch) return nil;
    return [self.sources faviconFor:item.url];
}

@end

#pragma mark - Public

BOOL ADCommandBarShow(NSWindow *window, BOOL newTab) {
    if (!window || ![NSStringFromClass(window.class) isEqualToString:@"Window.PlatformWindow"]) return NO;
    [[ADCommandBar shared] showInWindow:window mode:newTab ? ADCommandBarNewTab : ADCommandBarCurrentTab];
    return YES;
}
