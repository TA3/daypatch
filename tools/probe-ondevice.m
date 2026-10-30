// Dev tool: counts calls into Dia's on-device AI bridge (ArcAIService) while the
// app loads a few pages and uses the URL editor. Output: /tmp/daypatch-ondevice.txt.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdlib.h>

static NSCountedSet *gCalls;
static NSLock *gLock;

static void note(SEL s, id arg) {
    NSString *a = [arg isKindOfClass:NSString.class] ? [arg lastPathComponent] : (arg ? NSStringFromClass([arg class]) : @"");
    [gLock lock];
    [gCalls addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromSelector(s), a]];
    [gLock unlock];
}

// Every hooked method here has the shape -(void)x:(id)a ... with an object first argument;
// we forward with the original IMP typed as the widest signature in use.
#define HOOK2(sel) { SEL s = sel; Method m = class_getInstanceMethod(cls, s); \
    if (m) { __block IMP o = method_getImplementation(m); \
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id a, id b) { note(s, a); ((void (*)(id, SEL, id, id))o)(self, s, a, b); })); } }
#define HOOK3(sel) { SEL s = sel; Method m = class_getInstanceMethod(cls, s); \
    if (m) { __block IMP o = method_getImplementation(m); \
        method_setImplementation(m, imp_implementationWithBlock(^(id self, id a, id b, id c) { note(s, a); ((void (*)(id, SEL, id, id, id))o)(self, s, a, b, c); })); } }

static void after(double s, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }

__attribute__((constructor)) static void init(void) {
    gCalls = [NSCountedSet new];
    gLock = [NSLock new];
    Class cls = NSClassFromString(@"ArcAIService");
    HOOK2(@selector(initialize:callback:));
    HOOK2(@selector(loadClassifier:completion:));
    HOOK2(@selector(loadNomicEmbedText:completion:));
    HOOK2(@selector(nomicEmbed:completion:));
    HOOK2(@selector(loadInferenceModel:completion:));
    HOOK2(@selector(loadCommandBarRanking:completion:));
    HOOK2(@selector(getCompactBertClassificationFor:completion:));
    HOOK2(@selector(updateFeatureFlags:completion:));
    HOOK3(@selector(getClassificationFor:classifier:completion:));
    HOOK3(@selector(rankCommandBar:candidates:completion:));

    after(10, ^{
        NSWindow *w = nil;
        for (NSWindow *x in NSApp.windows) if ([NSStringFromClass(x.class) isEqualToString:@"Window.PlatformWindow"] && x.isVisible) w = x;
        void (*navigate)(NSWindow *, NSString *) = dlsym(RTLD_DEFAULT, "TweakNavigateWindow");
        NSArray *pages = @[@"https://en.wikipedia.org/wiki/Web_browser", @"https://news.ycombinator.com", @"https://developer.apple.com/documentation/appkit"];
        for (NSUInteger i = 0; i < pages.count; i++) after(i * 6, ^{ if (navigate) navigate(w, pages[i]); });
        after(pages.count * 6 + 2, ^{
            BOOL (*openEditor)(NSWindow *) = dlsym(RTLD_DEFAULT, "TweakSidebarFocusURLBar");
            if (openEditor) openEditor(w);
            after(1, ^{
                id fr = w.firstResponder;
                if ([fr respondsToSelector:@selector(insertText:)]) [fr insertText:@"wiki"];
                after(3, ^{
                    NSMutableString *out = [NSMutableString string];
                    [gLock lock];
                    for (NSString *k in [gCalls.allObjects sortedArrayUsingSelector:@selector(compare:)])
                        [out appendFormat:@"%4lu  %@\n", (unsigned long)[gCalls countForObject:k], k];
                    [gLock unlock];
                    [out writeToFile:@"/tmp/daypatch-ondevice.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                });
            });
        });
    });
}
