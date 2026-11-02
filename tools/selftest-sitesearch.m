// Dev tool: drives Site Search with real key events. Output: /tmp/ss.txt and /tmp/ss-*.png.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <objc/message.h>

static NSMutableString *out;
static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

static id bar(void) { return [NSClassFromString(@"TweakCommandBar") performSelector:@selector(shared)]; }
static NSPanel *panel(void) { return [bar() valueForKey:@"panel"]; }
static NSTextField *field(void) { return [bar() valueForKey:@"field"]; }
static NSString *text(void) { return field().currentEditor.string ?: field().stringValue; }

static void flush(void) { [out writeToFile:@"/tmp/ss.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil]; }

static void check(NSString *label, BOOL ok, NSString *seen) {
    [out appendFormat:@"%@ %@ [%@]\n", ok ? @"ok  " : @"FAIL", label, seen];
    flush();
}

static void snap(NSString *path) {
    NSView *v = panel().contentView.superview ?: panel().contentView;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void type(NSString *s) { [(NSTextView *)field().currentEditor insertText:s replacementRange:field().currentEditor.selectedRange]; }

static void keyMods(NSString *c, unsigned short code, NSEventModifierFlags mods) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:panel().windowNumber context:nil characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:code] atStart:NO];
}

static void key(NSString *c, unsigned short code) { keyMods(c, code, 0); }

// From inside Site Search with an empty field: `mods` + Backspace leaves it, Tab re-enters.
static void leaves(NSString *label, NSEventModifierFlags mods, dispatch_block_t next) {
    keyMods(@"\x7f", 51, mods);
    after(0.5, ^{
        check(label, ![bar() valueForKey:@"siteSearch"], [bar() valueForKey:@"typed"]);
        key(@"\t", 48);
        after(0.5, next);
    });
}

// Opens the bar, enters Site Search from `typed`, searches `query`, and expects `expected` in the new tab's URL.
static void search(NSWindow *w, NSString *typed, NSString *name, NSString *query, NSString *expected, dispatch_block_t next) {
    BOOL real = [NSStringFromClass(w.class) isEqualToString:@"Window.PlatformWindow"];
    NSString *(*urlFor)(NSWindow *) = dlsym(RTLD_DEFAULT, "TweakURLForWindow");
    // Calls the bar directly: a fresh test profile may only have Dia's onboarding window.
    ((void (*)(id, SEL, NSWindow *, NSInteger))objc_msgSend)(bar(), NSSelectorFromString(@"showInWindow:mode:"), w, 0);
    after(0.6, ^{
        type(typed);
        after(1, ^{
            NSTextField *hint = [bar() valueForKey:@"hint"];
            check([typed stringByAppendingString:@" shows the Tab hint"], !hint.hidden && [hint.stringValue containsString:name], hint.stringValue);
            snap([NSString stringWithFormat:@"/tmp/ss-%@-hint.png", typed]);
            key(@"\t", 48);
            after(0.5, ^{
                id engine = [bar() valueForKey:@"siteSearch"];
                check(@"Tab enters Site Search", [[engine valueForKey:@"name"] isEqual:name] && !text().length, [engine valueForKey:@"name"]);
                snap([NSString stringWithFormat:@"/tmp/ss-%@-pill.png", typed]);
                key(@"\x7f", 51);
                after(0.5, ^{
                    check(@"Backspace on empty leaves it", ![bar() valueForKey:@"siteSearch"] && [[bar() valueForKey:@"typed"] isEqual:typed], [bar() valueForKey:@"typed"]);
                    key(@"\t", 48);
                    after(0.5, ^{ leaves(@"Option-Backspace leaves it", NSEventModifierFlagOption, ^{ leaves(@"Command-Backspace leaves it", NSEventModifierFlagCommand, ^{
                        type(query);
                        after(0.5, ^{
                            snap([NSString stringWithFormat:@"/tmp/ss-%@-query.png", typed]);
                            NSArray *rows = [[bar() valueForKey:@"results"] valueForKey:@"items"];
                            NSString *rowURL = [rows.firstObject valueForKey:@"url"];
                            check([NSString stringWithFormat:@"the row searches %@", expected], rows.count == 1 && [rowURL containsString:expected], rowURL);
                            key(@"\r", 36);
                            after(4, ^{
                                check(@"Enter closes the bar", !panel().isVisible, @"");
                                if (real) { NSString *u = urlFor(w); check([NSString stringWithFormat:@"the tab opens %@", expected], [u containsString:expected], u); }
                                else [out appendString:@"note: onboarding window only, tab not checked\n"];
                                next();
                            });
                        });
                    }); }); });
                });
            });
        });
    });
}

static void run(int tries) {
    NSWindow *w = nil, *fallback = nil;
    for (NSWindow *x in NSApp.windows) {
        if (!x.isVisible) continue;
        if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"]) w = x;
        else if ([NSStringFromClass(x.class) containsString:@"Window"]) fallback = x;
    }
    if (!w && tries > 0) { after(2, ^{ run(tries - 1); }); return; }
    if (!w) w = fallback;
    if (!w) { check(@"found a window", NO, @"none"); return; }
    [NSApp activateIgnoringOtherApps:YES];
    [w makeKeyAndOrderFront:nil];
    // A long engine name must not squeeze the field out of the bar.
    ((void (*)(id, SEL, NSWindow *, NSInteger))objc_msgSend)(bar(), NSSelectorFromString(@"showInWindow:mode:"), w, 0);
    NSTextField *hint = [bar() valueForKey:@"hint"];
    hint.stringValue = [@"" stringByPaddingToLength:300 withString:@"long name " startingAtIndex:0];
    hint.hidden = NO;
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(bar(), NSSelectorFromString(@"layoutForRows:"), 0);
    check(@"a long hint leaves room for the field", NSWidth(field().frame) > 100 && NSWidth(hint.frame) <= NSWidth(panel().frame) / 2, NSStringFromRect(field().frame));
    search(w, @"redd", @"Reddit", @"cats & dogs", @"reddit.com/search/?q=cats%20%26%20dogs", ^{
        search(w, @"you", @"YouTube", @"lofi", @"youtube.com/results?search_query=lofi", ^{
            [out appendString:@"done\n"];
            flush();
        });
    });
}

__attribute__((constructor)) static void init(void) {
    out = [NSMutableString string];
    after(8, ^{ run(4); });
}
