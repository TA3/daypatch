// Dev tool: snapshots the UI daypatch adds or changes, for visual review.
//   /tmp/ui-palette.png   ⌘T palette with suggestions
//   /tmp/ui-sidebar.png   sidebar-anchored editor with suggestions
//   /tmp/ui-ntp.png       Dia's start page (opened via its own New Tab menu item)
//   /tmp/ui.txt           frames + the start page's view tree
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static NSView *find(NSView *v, NSString *needle) {
    if ([NSStringFromClass(v.class) containsString:needle]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, needle); if (h) return h; }
    return nil;
}

static void snapshot(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void dump(NSView *v, int d, int max) {
    NSString *extra = @"";
    if ([v isKindOfClass:NSTextField.class]) extra = [NSString stringWithFormat:@" \"%@\"", [(NSTextField *)v stringValue]];
    if ([v isKindOfClass:NSButton.class]) extra = [NSString stringWithFormat:@" btn=\"%@\" ax=\"%@\"", [(NSButton *)v title], v.accessibilityLabel];
    [out appendFormat:@"%*s%@ %@%@%@\n", d * 2, "", NSStringFromClass(v.class), NSStringFromRect(v.frame), v.hidden ? @" HIDDEN" : @"", extra];
    if (d < max && !v.hidden) for (NSView *s in v.subviews) dump(s, d + 1, max);
}

static void key(NSWindow *w, NSString *c, unsigned short code) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:w.windowNumber context:nil characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:code] atStart:NO];
}

static void frames(NSWindow *w, NSString *label) {
    NSView *pop = find(w.contentView.superview, @"DynamicPopover");
    NSView *sug = find(pop, @"BoostCommandBar.SuggestionsView");
    NSView *root = find(pop, @"BoostCommandBar.RootView");
    [out appendFormat:@"%@: popover=%@ root=%@ suggestions=%@\n", label, NSStringFromRect(pop.frame), NSStringFromRect(root.frame), NSStringFromRect(sug.frame)];
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        ((void (*)(NSWindow *, NSString *))dlsym(RTLD_DEFAULT, "TweakNavigateWindow"))(w, @"https://example.com");
        after(3, ^{
            ((BOOL (*)(NSWindow *))dlsym(RTLD_DEFAULT, "TweakPaletteOpen"))(w);
            after(1, ^{
                [w.firstResponder insertText:@"go"];
                after(2, ^{
                    frames(w, @"palette");
                    snapshot(w, @"/tmp/ui-palette.png");
                    key(w, @"\e", 53);
                    after(1.5, ^{
                        ((BOOL (*)(NSWindow *))dlsym(RTLD_DEFAULT, "TweakSidebarFocusURLBar"))(w);
                        after(1, ^{
                            id fr = w.firstResponder;
                            [fr selectAll:nil];
                            [fr insertText:@"go"];
                            after(2, ^{
                                frames(w, @"sidebar");
                                snapshot(w, @"/tmp/ui-sidebar.png");
                                key(w, @"\e", 53);
                                after(1.5, ^{
                                    // Dia's own start page, as on launch.
                                    for (NSMenuItem *top in NSApp.mainMenu.itemArray) for (NSMenuItem *i in top.submenu.itemArray)
                                        if ([i.title isEqualToString:@"New Tab"] && [i.keyEquivalent isEqualToString:@"t"]) [NSApp sendAction:i.action to:i.target from:i];
                                    after(2.5, ^{
                                        snapshot(w, @"/tmp/ui-ntp.png");
                                        dump(find(w.contentView.superview, @"NewTabPage.NewTabPageContentView"), 0, 7);
                                        // Where does the "Home" breadcrumb live?
                                        NSMutableArray *q = [NSMutableArray arrayWithObject:w.contentView.superview];
                                        while (q.count) {
                                            NSView *v = q.lastObject; [q removeLastObject];
                                            if ([v isKindOfClass:NSTextField.class] && [[(NSTextField *)v stringValue] isEqualToString:@"Home"] && !v.isHiddenOrHasHiddenAncestor) {
                                                [out appendString:@"HOME chain:"];
                                                for (NSView *s = v; s && ![NSStringFromClass(s.class) hasPrefix:@"ContentPane"]; s = s.superview)
                                                    [out appendFormat:@" < %@ %@", NSStringFromClass(s.class), NSStringFromRect(s.frame)];
                                                [out appendString:@"\n"];
                                            }
                                            [q addObjectsFromArray:v.subviews];
                                        }
                                        NSView *panel = find(w.contentView.superview, @"AssistantPanelRootView");
                                        [out appendFormat:@"ntp panel=%@\n", NSStringFromRect(panel.frame)];
                                        [out writeToFile:@"/tmp/ui.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
