// Dev tool: loaded alongside daypatch.dylib. Exercises the sidebar pill → Dia's
// URL editor, the settings pane, and the blocker. Writes /tmp/daypatch-selftest.txt
// and /tmp/daypatch-*.png.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;

static void snapshot(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview ?: w.contentView;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static NSView *find(NSView *v, NSString *needle) {
    if ([NSStringFromClass(v.class) containsString:needle]) return v;
    for (NSView *s in v.subviews) { NSView *h = find(s, needle); if (h) return h; }
    return nil;
}

static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static NSWindow *windowOfClass(NSString *needle) {
    for (NSWindow *w in NSApp.windows) if ([NSStringFromClass(w.class) containsString:needle] && w.isVisible) return w;
    return nil;
}

static void finish(void) { [out writeToFile:@"/tmp/daypatch-selftest.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil]; }

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        NSWindow *w = windowOfClass(@"Window.PlatformWindow");
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "ADNavigateWindow");
        NSUInteger (*blocked)(void) = dlsym(RTLD_DEFAULT, "ADBlockedRequestCount");
        BOOL (*openEditor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADSidebarFocusURLBar");
        navigate(w, @"https://example.com");
        after(3, ^{
            NSView *pill = find(w.contentView.superview, @"ADSidebarURLBar");
            NSView *nav = find(w.contentView.superview, @"NavigationBar.NavigationBarView");
            [out appendFormat:@"pill=%@ navbar hidden=%d\n", pill ? @"yes" : @"no", nav.hidden];
            [out appendFormat:@"menu Focus Chat hidden: "];
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) for (NSMenuItem *i in top.submenu.itemArray)
                if ([i.title isEqualToString:@"Focus Chat"]) [out appendFormat:@"%d\n", i.hidden];
            NSView *chats = find(w.contentView.superview, @"LibraryCellView");
            [out appendFormat:@"Chats cell hidden=%d\n", chats.isHiddenOrHasHiddenAncestor];
            BOOL opened = openEditor(w);
            after(1, ^{
                id fr = w.firstResponder;
                [out appendFormat:@"editor opened=%d firstResponder=%@\n", opened, NSStringFromClass([fr class])];
                if ([fr respondsToSelector:@selector(insertText:)]) [fr insertText:@"git"];
                after(2, ^{
                    NSView *pop = find(w.contentView.superview, @"DynamicPopover");
                    NSRect pf = [pop convertRect:pop.bounds toView:nil];
                    NSRect pillRect = [pill convertRect:pill.bounds toView:nil];
                    [out appendFormat:@"popover frame=%@ pill=%@\n", NSStringFromRect(pf), NSStringFromRect(pillRect)];
                    NSView *caps = find(pop, @"AssistantCapabilitiesToolbarView");
                    [out appendFormat:@"Add tabs or files hidden=%d\n", caps ? caps.isHiddenOrHasHiddenAncestor : -1];
                    NSView *nav2 = find(w.contentView.superview, @"NavigationBar.NavigationBarView");
                    NSView *content = find(w.contentView.superview, @"GesturalNavigationEventInterceptorView");
                    [out appendFormat:@"while editing: navbar hidden=%d content=%@\n", nav2.hidden, NSStringFromRect(content.frame)];
                    snapshot(w, @"/tmp/daypatch-editor.png");
                    // Esc out, then check nothing is left at the top.
                    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:w.windowNumber
                                                       context:nil characters:@"\e" charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53] atStart:NO];
                    after(2, ^{
                        NSView *content2 = find(w.contentView.superview, @"GesturalNavigationEventInterceptorView");
                        [out appendFormat:@"after esc: popover=%@ content=%@\n", find(w.contentView.superview, @"DynamicPopover") ? @"open" : @"closed", NSStringFromRect(content2.frame)];
                        snapshot(w, @"/tmp/daypatch-after-esc.png");
                        [out appendFormat:@"blocked so far=%lu\n", (unsigned long)blocked()];
                        for (NSMenuItem *i in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray)
                            if ([i.keyEquivalent isEqualToString:@","]) [NSApp sendAction:i.action to:i.target from:i];
                        after(2, ^{
                            NSWindow *p = windowOfClass(@"Preferences");
                            NSTableView *t = (NSTableView *)find(p.contentView, @"NSTableView");
                            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:t.numberOfRows - 1] byExtendingSelection:NO];
                            after(1.5, ^{
                                snapshot(p, @"/tmp/daypatch-prefs.png");
                                [p close];
                                finish();
                            });
                        });
                    });
                });
            });
        });
    });
}
