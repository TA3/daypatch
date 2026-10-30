// Dev tool: logs every URLSession request host/path made by Dia's native layer and
// lists visible AI-related views/menu items. Output: /tmp/daypatch-ai.txt after 45 s.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

static NSMutableOrderedSet<NSString *> *gSeen;
static NSLock *gLock;

@interface ADLogProtocol : NSURLProtocol
@end

@implementation ADLogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r {
    NSURL *u = r.URL;
    NSString *path = u.path.length > 40 ? [u.path substringToIndex:40] : u.path;
    [gLock lock];
    [gSeen addObject:[NSString stringWithFormat:@"%@ %@%@", r.HTTPMethod, u.host, path]];
    [gLock unlock];
    return NO;
}
@end

static NSURLSession *(*origSession)(id, SEL, NSURLSessionConfiguration *, id, NSOperationQueue *);
static NSURLSession *hookedSession(id self, SEL _cmd, NSURLSessionConfiguration *c, id d, NSOperationQueue *q) {
    c.protocolClasses = [@[ADLogProtocol.class] arrayByAddingObjectsFromArray:c.protocolClasses ?: @[]];
    return origSession(self, _cmd, c, d, q);
}

static void walk(NSView *v, NSRegularExpression *re, NSMutableString *out, NSString *path) {
    NSString *name = NSStringFromClass(v.class);
    if ([re firstMatchInString:name options:0 range:NSMakeRange(0, name.length)] && !v.isHiddenOrHasHiddenAncestor && NSWidth(v.frame) > 0)
        [out appendFormat:@"VIEW %@ %@ in %@\n", name, NSStringFromRect([v convertRect:v.bounds toView:nil]), path];
    for (NSView *s in v.subviews) walk(s, re, out, [NSString stringWithFormat:@"%@>%@", path.length > 200 ? @"…" : path, name.length > 40 ? [name substringFromIndex:name.length - 40] : name]);
}

__attribute__((constructor)) static void init(void) {
    gSeen = [NSMutableOrderedSet orderedSet];
    gLock = [NSLock new];
    [NSURLProtocol registerClass:ADLogProtocol.class];
    Method m = class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:));
    origSession = (void *)method_setImplementation(m, (IMP)hookedSession);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSMutableString *out = [NSMutableString string];
        [gLock lock];
        for (NSString *s in gSeen) [out appendFormat:@"NET %@\n", s];
        [gLock unlock];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?i)assistant|chat|ask|skill|brief|personal|agent|clia|memory|suggest" options:0 error:nil];
        for (NSWindow *w in NSApp.windows) if (w.isVisible) walk(w.contentView.superview, re, out, @"");
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *i in top.submenu.itemArray) {
                NSString *t = i.title;
                if ([re firstMatchInString:t options:0 range:NSMakeRange(0, t.length)])
                    [out appendFormat:@"MENU %@ > %@ [%@]\n", top.title, t, i.keyEquivalent];
            }
        NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryRepresentation];
        for (NSString *k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)])
            if ([re firstMatchInString:k options:0 range:NSMakeRange(0, k.length)] || [k.lowercaseString containsString:@"telemetry"] || [k.lowercaseString containsString:@"datadog"] || [k.lowercaseString containsString:@"extraction"])
                [out appendFormat:@"DEFAULT %@ = %@\n", k, [[d[k] description] substringToIndex:MIN((NSUInteger)80, [d[k] description].length)]];
        [out writeToFile:@"/tmp/daypatch-ai.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
