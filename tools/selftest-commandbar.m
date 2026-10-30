// Dev tool: exercises daypatch's command bar. Output: /tmp/cb.txt and /tmp/cb-*.png.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static id bar(void) { return [NSClassFromString(@"ADCommandBar") performSelector:@selector(shared)]; }
static NSPanel *panel(void) { return [bar() valueForKey:@"panel"]; }
static NSArray *items(void) { return [[bar() valueForKey:@"results"] valueForKey:@"items"]; }
static NSTextField *field(void) { return [bar() valueForKey:@"field"]; }

static void snap(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview ?: w.contentView;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void listItems(NSString *label) {
    [out appendFormat:@"[%@] field=\"%@\" panel=%@\n", label, field().currentEditor.string ?: field().stringValue, NSStringFromRect(panel().frame)];
    NSArray *kinds = @[@"search", @"url", @"command", @"page", @"tab", @"bookmark", @"history"];
    for (id it in items()) [out appendFormat:@"   %-8@ %@ — %@  (%.1f)\n", kinds[[[it valueForKey:@"kind"] integerValue]], [it valueForKey:@"title"], [it valueForKey:@"detail"], [[it valueForKey:@"score"] doubleValue]];
}

static void type(NSString *s) {
    NSTextView *ed = (NSTextView *)field().currentEditor;
    [ed selectAll:nil];
    [ed insertText:s];  // posts the text-did-change notification like real typing
}

static void key(NSWindow *w, NSString *c, unsigned short code, NSEventModifierFlags mods) {
    NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:NSProcessInfo.processInfo.systemUptime
                              windowNumber:w.windowNumber context:nil characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:code];
    [NSApp postEvent:e atStart:NO];
}

static NSUInteger tabCount(NSWindow *w) {
    for (id sw in [NSApp valueForKey:@"appleScriptWindows"]) if ([[sw valueForKey:@"windowId"] isEqual:w.identifier]) return [[sw valueForKey:@"appleScriptTabs"] count];
    return 0;
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        [NSApp activateIgnoringOtherApps:YES];
        [w makeKeyAndOrderFront:nil];
        BOOL (*show)(NSWindow *, BOOL) = dlsym(RTLD_DEFAULT, "ADCommandBarShow");
        NSString *(*urlFor)(NSWindow *) = dlsym(RTLD_DEFAULT, "ADURLForWindow");
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "ADNavigateWindow");
        navigate(w, @"https://example.com/cb-start");
        NSArray *cmds = [[bar() valueForKey:@"sources"] performSelector:@selector(loadCommands)];
        [out appendFormat:@"commands loaded: %lu %@\n", (unsigned long)cmds.count, [[cmds valueForKey:@"title"] componentsJoinedByString:@" | "]];
        after(3, ^{
            show(w, YES);
            after(0.8, ^{
                listItems(@"⌘T empty");
                snap(panel(), @"/tmp/cb-empty.png");
                type(@"setti");
                after(1, ^{
                    listItems(@"setti");
                    snap(panel(), @"/tmp/cb-setti.png");
                    type(@"flags");
                    after(1, ^{
                        listItems(@"flags");
                        type(@"go");
                        after(1, ^{
                            listItems(@"go");
                            snap(panel(), @"/tmp/cb-go.png");
                            type(@"example.org/cmdbar");
                            after(1, ^{
                                NSUInteger before = tabCount(w);
                                key(panel(), @"\r", 36, 0);
                                after(3, ^{
                                    [out appendFormat:@"enter url: tabs %lu -> %lu active=%@ panel=%@\n", (unsigned long)before, (unsigned long)tabCount(w), urlFor(w), panel().isVisible ? @"open" : @"closed"];
                                    // ⌘L: current-tab mode, pre-filled; pick a tab result.
                                    show(w, NO);
                                    after(0.8, ^{
                                        listItems(@"⌘L prefilled");
                                        type(@"cb-start");
                                        after(1, ^{
                                            listItems(@"cb-start");
                                            key(panel(), @"\r", 36, 0);
                                            after(2.5, ^{
                                                [out appendFormat:@"tab switch: active=%@\n", urlFor(w)];
                                                navigate(w, @"chrome://flags");
                                                after(2.5, ^{
                                                    [out appendFormat:@"chrome://flags -> %@\n", urlFor(w)];
                                                    show(w, YES);
                                                    after(0.8, ^{
                                                        type(@"setti");
                                                        after(1, ^{
                                                            key(panel(), @"\r", 36, 0);
                                                            after(2, ^{
                                                                BOOL prefs = NO;
                                                                for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) containsString:@"Preferences"] && x.isVisible) prefs = YES;
                                                                [out appendFormat:@"settings command: prefs window=%d\n", prefs];
                                                                [out writeToFile:@"/tmp/cb.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                                                            });
                                                        });
                                                    });
                                                });
                                            });
                                        });
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
