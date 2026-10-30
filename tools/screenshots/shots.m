// Dev tool: renders README screenshots of the command bar and the Settings pane
// from the real view code, with generic demo content (no personal data, no
// third-party logos). Output: <dir>/commandbar.png, <dir>/settings.png (2x).
//
//   clang -fobjc-arc -framework AppKit -framework QuartzCore -lsqlite3 \
//     tools/screenshots/shots.m $(ls src/*.m | grep -v DayPatch.m) -o build/shots && build/shots build/shots-out
#import <AppKit/AppKit.h>
#import "../../src/CommandSources.h"

static NSImage *letterIcon(NSString *letter, NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(20, 20) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:5 yRadius:5] fill];
        NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold], NSForegroundColorAttributeName: NSColor.whiteColor};
        NSSize s = [letter sizeWithAttributes:a];
        [letter drawAtPoint:NSMakePoint(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2) withAttributes:a];
        return YES;
    }];
}

@interface DemoDelegate : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, NSImage *> *icons;
@end
@implementation DemoDelegate
- (NSImage *)iconForItem:(TweakItem *)item { return item.url ? self.icons[item.url] : nil; }
- (void)resultsView:(id)v activate:(NSInteger)row {}
@end

static TweakItem *item(TweakItemKind kind, NSString *title, NSString *detail, NSString *url, NSString *symbol) {
    TweakItem *i = [TweakItem new];
    i.kind = kind; i.title = title; i.detail = detail; i.url = url; i.symbol = symbol;
    return i;
}

@interface BarBackground : NSView
@end
@implementation BarBackground
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:16 yRadius:16];
    [[NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.13 alpha:0.97] setFill]; [p fill];
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; p.lineWidth = 1; [p stroke];
}
@end

static void writePNG(NSView *v, NSString *path) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    // Render at 2x for crisp README images.
    rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)NSWidth(v.bounds) * 2 pixelsHigh:(NSInteger)NSHeight(v.bounds) * 2
                                               bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = v.bounds.size;
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void commandBar(NSString *dir) {
    NSArray *items = @[
        item(TweakItemCommand, @"Settings", @"⌘,", nil, @"gearshape"),
        item(TweakItemSearch, @"set", @"Search Google", @"https://www.google.com/search?q=set", @"magnifyingglass"),
        item(TweakItemTab, @"Settings · Project board", @"Switch to Tab", @"https://board.example.com/settings", @"square.on.square"),
        item(TweakItemHistory, @"Account settings", nil, @"https://example.com/account/settings", @"globe"),
        item(TweakItemPage, @"Site Settings", nil, @"chrome://settings/content", @"slider.horizontal.3"),
        item(TweakItemHistory, @"Settings reference", nil, @"https://docs.example.org/reference/settings", @"globe"),
    ];
    DemoDelegate *del = [DemoDelegate new];
    del.icons = @{
        @"https://board.example.com/settings": letterIcon(@"P", [NSColor colorWithSRGBRed:0.36 green:0.47 blue:0.98 alpha:1]),
        @"https://example.com/account/settings": letterIcon(@"E", [NSColor colorWithSRGBRed:0.95 green:0.55 blue:0.25 alpha:1]),
        @"https://docs.example.org/reference/settings": letterIcon(@"D", [NSColor colorWithSRGBRed:0.20 green:0.70 blue:0.55 alpha:1]),
    };

    CGFloat width = 760, input = 64, rows = items.count * 44 + 16;
    BarBackground *bar = [[BarBackground alloc] initWithFrame:NSMakeRect(0, 0, width, input + 1 + rows)];
    bar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil]];
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.frame = NSMakeRect(22, input / 2 - 12, 24, 24);
    [bar addSubview:icon];

    NSTextField *field = [NSTextField labelWithString:@""];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"set"
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:22 weight:NSFontWeightMedium], NSForegroundColorAttributeName: NSColor.labelColor}];
    field.attributedStringValue = text;
    field.frame = NSMakeRect(58, input / 2 - 14, 200, 30);
    [bar addSubview:field];
    NSBox *caret = [[NSBox alloc] initWithFrame:NSMakeRect(58 + [text size].width + 2, input / 2 - 12, 2, 26)];
    caret.boxType = NSBoxCustom; caret.borderWidth = 0; caret.fillColor = NSColor.controlAccentColor;
    [bar addSubview:caret];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(0, input, width, 1)];
    divider.boxType = NSBoxSeparator;
    [bar addSubview:divider];

    NSView *results = [[NSClassFromString(@"TweakResultsView") alloc] initWithFrame:NSMakeRect(0, input + 1, width, rows)];
    [results setValue:del forKey:@"delegate"];
    [results setValue:items forKey:@"items"];
    [bar addSubview:results];

    writePNG(bar, [dir stringByAppendingPathComponent:@"commandbar.png"]);
}

static void settings(NSString *dir) {
    NSView *pane = [[NSClassFromString(@"TweakPrefsPane") alloc] initWithFrame:NSMakeRect(0, 0, 600, 1080)];
    pane.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSView *bg = [[NSView alloc] initWithFrame:pane.frame];
    bg.wantsLayer = YES;
    bg.layer.backgroundColor = [NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.13 alpha:1].CGColor;
    bg.appearance = pane.appearance;
    [bg addSubview:pane];
    [bg layoutSubtreeIfNeeded];
    // Keep the first three groups (URL bar, Sidebar URL bar, Privacy): crop to the top.
    NSView *crop = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 708)];
    crop.wantsLayer = YES;
    crop.layer.backgroundColor = bg.layer.backgroundColor;
    crop.appearance = pane.appearance;
    bg.frame = NSMakeRect(0, 708 - 1080, 600, 1080);
    [crop addSubview:bg];
    writePNG(crop, [dir stringByAppendingPathComponent:@"settings.png"]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSString *dir = argc > 1 ? @(argv[1]) : @".";
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [NSAppearance setCurrentAppearance:NSApp.appearance];
        commandBar(dir);
        settings(dir);
        printf("wrote %s/commandbar.png, settings.png\n", dir.UTF8String);
    }
    return 0;
}
