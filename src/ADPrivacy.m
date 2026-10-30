// Privacy: hides Dia's AI surfaces and blocks AI + telemetry hosts.
//
// Blocking happens in two layers:
//  1. Chromium (web engine + its network service): --host-resolver-rules added to
//     argv before main(), so blocked hosts fail DNS. Applied at launch only.
//  2. Dia's native Swift layer (URLSession): an NSURLProtocol that fails requests
//     to blocked hosts, and WebSocket tasks redirected to an invalid host.
#import "ADCommon.h"
#import <objc/runtime.h>
#include <spawn.h>

NSString *const ADKeyHideAI = @"daypatch.hideAI";
NSString *const ADKeyBlockAI = @"daypatch.blockAI";
NSString *const ADKeyBlockTelemetry = @"daypatch.blockTelemetry";

static NSUInteger gBlockedCount;
static NSLock *gLock;

NSArray<NSString *> *ADAIHosts(void) {
    return @[@"aiproxy.diabrowser.engineering", @"ai-service.diabrowser.engineering",
             @"ai-service.staging.diabrowser.engineering", @"ai-service-eval.diabrowser.engineering",
             @"websearch.diabrowser.engineering", @"webresultproxy.diabrowser.engineering",
             @"artifactcdn.diabrowser.engineering", @"generativelanguage.googleapis.com"];
}

NSArray<NSString *> *ADTelemetryHosts(void) {
    // LaunchDarkly *flag* fetches (clientstream/clientsdk) stay allowed: Dia needs them to start.
    return @[@"browser-intake-datadoghq.com", @"datadoghq.com", @"ingest.us.sentry.io", @"sentry.io",
             @"api.segment.io", @"cdn-settings.segment.com", @"segment.io",
             @"mobile.launchdarkly.com", @"events.launchdarkly.com",
             @"otel-gateway.diabrowser.engineering"];
}

static NSArray<NSString *> *blockedHosts(void) {
    NSMutableArray *h = [NSMutableArray array];
    if ([ADSettings boolForKey:ADKeyBlockAI]) [h addObjectsFromArray:ADAIHosts()];
    if ([ADSettings boolForKey:ADKeyBlockTelemetry]) [h addObjectsFromArray:ADTelemetryHosts()];
    return h;
}

static BOOL isBlocked(NSString *host) {
    host = host.lowercaseString;
    if (!host.length) return NO;
    for (NSString *b in blockedHosts())
        if ([host isEqualToString:b] || [host hasSuffix:[@"." stringByAppendingString:b]]) return YES;
    return NO;
}

NSUInteger ADBlockedRequestCount(void) {
    [gLock lock];
    NSUInteger n = gBlockedCount;
    [gLock unlock];
    return n;
}

static void noteBlocked(NSURL *url) {
    [gLock lock];
    gBlockedCount++;
    [gLock unlock];
    NSLog(@"[daypatch] blocked %@", url.host);
}

#pragma mark - URLSession layer

@interface ADBlockProtocol : NSURLProtocol
@end

@implementation ADBlockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return isBlocked(r.URL.host); }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    noteBlocked(self.request.URL);
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil]];
}
- (void)stopLoading {}
@end

static NSURLSession *(*origSessionWithConfig)(id, SEL, NSURLSessionConfiguration *, id, NSOperationQueue *);
static NSURLSession *hookedSessionWithConfig(id self, SEL _cmd, NSURLSessionConfiguration *c, id d, NSOperationQueue *q) {
    if (c && ![c.protocolClasses containsObject:ADBlockProtocol.class])
        c.protocolClasses = [@[ADBlockProtocol.class] arrayByAddingObjectsFromArray:c.protocolClasses ?: @[]];
    return origSessionWithConfig(self, _cmd, c, d, q);
}

static NSURLSession *(*origSessionWithConfigOnly)(id, SEL, NSURLSessionConfiguration *);
static NSURLSession *hookedSessionWithConfigOnly(id self, SEL _cmd, NSURLSessionConfiguration *c) {
    if (c && ![c.protocolClasses containsObject:ADBlockProtocol.class])
        c.protocolClasses = [@[ADBlockProtocol.class] arrayByAddingObjectsFromArray:c.protocolClasses ?: @[]];
    return origSessionWithConfigOnly(self, _cmd, c);
}

// NSURLProtocol doesn't see WebSocket tasks; point blocked ones at an unroutable host.
static NSURL *wsRewrite(NSURL *u) {
    if (!isBlocked(u.host)) return u;
    noteBlocked(u);
    return [NSURL URLWithString:@"wss://blocked.invalid/"];
}
static id (*origWSURL)(id, SEL, NSURL *);
static id hookedWSURL(id self, SEL _cmd, NSURL *u) { return origWSURL(self, _cmd, wsRewrite(u)); }
static id (*origWSURLProtocols)(id, SEL, NSURL *, NSArray *);
static id hookedWSURLProtocols(id self, SEL _cmd, NSURL *u, NSArray *p) { return origWSURLProtocols(self, _cmd, wsRewrite(u), p); }
static id (*origWSRequest)(id, SEL, NSURLRequest *);
static id hookedWSRequest(id self, SEL _cmd, NSURLRequest *r) {
    if (!isBlocked(r.URL.host)) return origWSRequest(self, _cmd, r);
    NSMutableURLRequest *m = [r mutableCopy];
    m.URL = wsRewrite(r.URL);
    return origWSRequest(self, _cmd, m);
}

#pragma mark - Chromium layer (command line)

// Dia starts Chromium from an ArcBrowserApplicationConfiguration whose argc/argv
// getters supply the command line; append --host-resolver-rules there.
static NSString *resolverSwitch(void) {
    NSArray *hosts = blockedHosts();
    if (!hosts.count) return nil;
    NSMutableArray *rules = [NSMutableArray array];
    for (NSString *h in hosts) {
        [rules addObject:[NSString stringWithFormat:@"MAP %@ ~NOTFOUND", h]];
        [rules addObject:[NSString stringWithFormat:@"MAP *.%@ ~NOTFOUND", h]];
    }
    return [@"--host-resolver-rules=" stringByAppendingString:[rules componentsJoinedByString:@","]];
}

// Marks the command line as already extended (so repeated getter calls don't append twice).
static NSString *const kMarker = @"--daypatch";

static int (*origArgc)(id, SEL);
static NSArray *(*origArgv)(id, SEL);

static BOOL hasSwitch(NSArray *argv) { return [argv containsObject:kMarker]; }

static NSArray *hookedArgv(id self, SEL _cmd) {
    NSArray *argv = origArgv(self, _cmd);
    if (hasSwitch(argv) || (argv.count && ![argv.firstObject isKindOfClass:NSString.class])) return argv;
    NSMutableArray *extra = [ADPerformanceSwitches() mutableCopy];
    NSString *sw = resolverSwitch();
    if (sw) [extra addObject:sw];
    [extra addObject:kMarker];
    return [argv arrayByAddingObjectsFromArray:extra];
}

static int hookedArgc(id self, SEL _cmd) {
    NSArray *argv = origArgv(self, @selector(argv));
    return (int)hookedArgv(self, @selector(argv)).count - (int)argv.count + origArgc(self, _cmd);
}

void ADPrivacyPatchArgv(void) {
    Class cls = NSClassFromString(@"ArcBrowserApplicationConfiguration");
    if (!cls) { NSLog(@"[daypatch] ArcBrowserApplicationConfiguration not found; web-engine blocking inactive"); return; }
    origArgv = (void *)ADHook(cls, @selector(argv), (IMP)hookedArgv);
    origArgc = (void *)ADHook(cls, @selector(argc), (IMP)hookedArgc);
}

#pragma mark - Local agent runtime

// Dia's AgentServerManager posix_spawns Resources/agent-server-resources/dist/agent-server
// (a local agent runtime on 127.0.0.1). Don't start it while AI features are hidden.
// dyld interposing applies because daypatch is an inserted library.
static BOOL refuseSpawn(const char *path) {
    if (!path || !strstr(path, "agent-server-resources")) return NO;
    if (![ADSettings boolForKey:ADKeyHideAI]) return NO;
    static int logged;
    if (logged++ < 3) NSLog(@"[daypatch] not starting agent-server");
    return YES;
}

static int ad_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *fa,
                          const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (refuseSpawn(path)) return EPERM;
    return posix_spawn(pid, path, fa, attr, argv, envp);
}

static int ad_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *fa,
                           const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (refuseSpawn(file)) return EPERM;
    return posix_spawnp(pid, file, fa, attr, argv, envp);
}

__attribute__((used)) static const struct { const void *replacement, *original; } interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    {(const void *)ad_posix_spawn, (const void *)posix_spawn},
    {(const void *)ad_posix_spawnp, (const void *)posix_spawnp},
};

#pragma mark - Hiding AI UI

static NSArray<NSString *> *aiMenuTitles(void) {
    return @[@"Chat…", @"New Chat", @"Focus Chat", @"Send Chat Prompt Now", @"Open Daily Brief", @"Personalize Dia"];
}

static void applyMenus(void) {
    BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
    NSArray *titles = aiMenuTitles();
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *i in top.submenu.itemArray)
            if ([titles containsObject:i.title] && i.hidden != hide) i.hidden = hide;  // hidden items also lose their shortcuts
}

static void hideMatching(NSView *parent, BOOL hide, BOOL (^match)(NSView *)) {
    for (NSView *v in parent.subviews) if (match(v) && v.hidden != hide) v.hidden = hide;
}

// Footer: "Chats" library cell.
static void (*origFooterLayout)(id, SEL);
static void hookedFooterLayout(NSView *self, SEL _cmd) {
    origFooterLayout(self, _cmd);
    if ([ADSettings boolForKey:ADKeyHideAI])
        hideMatching(self, YES, ^BOOL(NSView *v) { return [NSStringFromClass(v.class) isEqualToString:@"TabSidebar.LibraryCellView"]; });
}

// Top bar: "Chat with this tab", personalization and skills buttons.
static void (*origBarLayout)(id, SEL);
static void hookedBarLayout(NSView *self, SEL _cmd) {
    origBarLayout(self, _cmd);
    if (![ADSettings boolForKey:ADKeyHideAI]) return;
    for (NSView *row in self.subviews)
        hideMatching(row, YES, ^BOOL(NSView *v) {
            NSString *c = NSStringFromClass(v.class);
            if ([c hasPrefix:@"AssistantPersonalityUI."]) return YES;
            return [c isEqualToString:@"NavigationBar.NavigationBarCapsuleButton"] && [v.accessibilityLabel containsString:@"Chat"];
        });
}

// New tab page: the Dia logo above the composer. The composer itself stays: it is
// also Dia's URL/search box.
static void (*origNTPLayout)(id, SEL);
static void hookedNTPLayout(NSView *self, SEL _cmd) {
    origNTPLayout(self, _cmd);
    BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
    for (NSView *holder in self.subviews)
        hideMatching(holder, hide, ^BOOL(NSView *v) {
            NSString *c = NSStringFromClass(v.class);
            return [c hasPrefix:@"Personalization."] || [c hasPrefix:@"PowerUp."];
        });
}

// Tab hover card: "Chat with this tab" and "Create context bundle" (tabs handed to
// the AI). Matched by the action button class and its tooltip.
static BOOL isAIHoverAction(NSView *b) {
    NSString *t = b.toolTip ?: b.accessibilityLabel;
    return [t isEqualToString:@"Chat with this tab"] || [t isEqualToString:@"Create context bundle"];
}
static void applyHoverAction(NSView *b) {
    if (isAIHoverAction(b)) {
        BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
        if (b.hidden != hide) b.hidden = hide;
    }
}
static void (*origActionSetToolTip)(id, SEL, NSString *);
static void hookedActionSetToolTip(NSView *self, SEL _cmd, NSString *tip) {
    origActionSetToolTip(self, _cmd, tip);
    applyHoverAction(self);
}
static void (*origActionMoveToWindow)(id, SEL);
static void hookedActionMoveToWindow(NSView *self, SEL _cmd) {
    origActionMoveToWindow(self, _cmd);
    applyHoverAction(self);
}

// URL editor / composer: placeholder reads as a URL bar, not a chat box.
static NSString *const kURLPlaceholder = @"Search or enter URL";
static NSAttributedString *urlPlaceholder(NSAttributedString *ph) {
    if (!ph.length || ![ADSettings boolForKey:ADKeyHideAI] || [ph.string isEqualToString:kURLPlaceholder]) return ph;
    return [[NSAttributedString alloc] initWithString:kURLPlaceholder attributes:[ph attributesAtIndex:0 effectiveRange:NULL]];
}

// Dia's Swift code stores the placeholder directly, but AppKit reads it back
// through the Objective-C getter when drawing, so substitute it there.
static NSAttributedString *(*origPlaceholderGetter)(id, SEL);
static NSAttributedString *hookedPlaceholderGetter(id self, SEL _cmd) {
    return urlPlaceholder(origPlaceholderGetter(self, _cmd));
}

// URL editor / composer: the bottom toolbar (mic, "Think more", Go) is all AI
// controls apart from Go, which Return already does.
static void (*origToolbarLayout)(id, SEL);
static void hookedToolbarLayout(NSView *self, SEL _cmd) {
    origToolbarLayout(self, _cmd);
    BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
    if (self.hidden != hide) self.hidden = hide;
}

// With the toolbar hidden Dia still reserves its height under the suggestion list,
// clipping the last rows. Let the list run to the bottom instead.
static const CGFloat kSuggestionsBottomPad = 8;
static void (*origSuggestionsSetFrame)(id, SEL, NSRect);
static void hookedSuggestionsSetFrame(NSView *self, SEL _cmd, NSRect f) {
    NSView *toolbar = nil;
    for (NSView *s in self.superview.subviews)
        if ([NSStringFromClass(s.class) isEqualToString:@"BoostCommandBar.ToolbarView"]) toolbar = s;
    if (toolbar.hidden && NSHeight(f) > 0 && self.superview.isFlipped)
        f.size.height = MAX(0, NSHeight(self.superview.bounds) - NSMinY(f) - kSuggestionsBottomPad);
    origSuggestionsSetFrame(self, _cmd, f);
}

// The start page's composer has the same reserved toolbar space; trim it while
// Dia's proposed height still includes the (hidden) toolbar.
static void (*origPanelSetFrame)(id, SEL, NSRect);
static BOOL inPopover(NSView *v) {
    for (NSView *s = v.superview; s; s = s.superview)
        if ([NSStringFromClass(s.class) containsString:@"DynamicPopover"]) return YES;  // sized by ADNavBar's popover hook
    return NO;
}

static void hookedPanelSetFrame(NSView *self, SEL _cmd, NSRect f) {
    NSView *toolbar = ADDescendantOfClass(self, @"BoostCommandBar.ToolbarView");
    if (toolbar.hidden && !inPopover(self) && NSHeight(f) >= NSMaxY(toolbar.frame) - 1 && NSHeight(f) > NSHeight(toolbar.frame))
        f.size.height -= NSHeight(toolbar.frame);
    origPanelSetFrame(self, _cmd, f);
}

// URL editor / composer: the "Add tabs or files" (attach context for the AI) row.
static void (*origCapsLayout)(id, SEL);
static void hookedCapsLayout(NSView *self, SEL _cmd) {
    origCapsLayout(self, _cmd);
    BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
    if (self.hidden != hide) self.hidden = hide;
}

static void applyDefaults(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL hide = [ADSettings boolForKey:ADKeyHideAI];
    // Page content extraction feeds the assistant; Dia defaults it on.
    [d setBool:!hide forKey:@"enablePageContentExtraction"];
    if (hide) [d setBool:YES forKey:@"hasManuallyClosedAskOnPage"];
    [d setInteger:[ADSettings boolForKey:ADKeyBlockTelemetry] ? 0 : 100 forKey:@"datadogTracesSamplingRate"];
}

static void hookLayout(NSString *className, IMP imp, void (**orig)(id, SEL)) {
    Class c = NSClassFromString(className);
    if (c) *orig = (void *)ADHook(c, @selector(layout), imp);
    else NSLog(@"[daypatch] %@ not found", className);
}

static void relayoutWindows(void) {
    for (NSWindow *w in NSApp.windows) {
        NSMutableArray *queue = [NSMutableArray arrayWithObject:w.contentView.superview ?: w.contentView];
        while (queue.count) {
            NSView *v = queue.lastObject;
            [queue removeLastObject];
            NSString *c = NSStringFromClass(v.class);
            if ([c isEqualToString:@"TabSidebar.SidebarContainerFooterView"] || [c isEqualToString:@"NavigationBar.NavigationBarView"] ||
                [c isEqualToString:@"NewTabPage.NewTabPageContentView"]) {
                // Un-hide what we hid; Dia's layout then re-applies its own state.
                for (NSView *s in v.subviews) {
                    if ([NSStringFromClass(s.class) isEqualToString:@"TabSidebar.LibraryCellView"]) s.hidden = NO;
                    for (NSView *g in s.subviews) {
                        NSString *gc = NSStringFromClass(g.class);
                        if ([gc hasPrefix:@"Personalization."] || [gc hasPrefix:@"PowerUp."] || [gc hasPrefix:@"AssistantPersonalityUI."] ||
                            ([gc isEqualToString:@"NavigationBar.NavigationBarCapsuleButton"] && [g.accessibilityLabel containsString:@"Chat"]))
                            g.hidden = NO;
                    }
                }
                v.needsLayout = YES;
            }
            [queue addObjectsFromArray:v.subviews];
        }
    }
}

void ADPrivacyInstall(void) {
    gLock = [NSLock new];
    [NSURLProtocol registerClass:ADBlockProtocol.class];
    Class meta = object_getClass(NSURLSession.class);
    origSessionWithConfig = (void *)ADHook(meta, @selector(sessionWithConfiguration:delegate:delegateQueue:), (IMP)hookedSessionWithConfig);
    origSessionWithConfigOnly = (void *)ADHook(meta, @selector(sessionWithConfiguration:), (IMP)hookedSessionWithConfigOnly);
    origWSURL = (void *)ADHook(NSURLSession.class, @selector(webSocketTaskWithURL:), (IMP)hookedWSURL);
    origWSURLProtocols = (void *)ADHook(NSURLSession.class, @selector(webSocketTaskWithURL:protocols:), (IMP)hookedWSURLProtocols);
    origWSRequest = (void *)ADHook(NSURLSession.class, @selector(webSocketTaskWithRequest:), (IMP)hookedWSRequest);

    dispatch_async(dispatch_get_main_queue(), ^{
        hookLayout(@"TabSidebar.SidebarContainerFooterView", (IMP)hookedFooterLayout, &origFooterLayout);
        hookLayout(@"NavigationBar.NavigationBarView", (IMP)hookedBarLayout, &origBarLayout);
        hookLayout(@"NewTabPage.NewTabPageContentView", (IMP)hookedNTPLayout, &origNTPLayout);
        hookLayout(@"AssistantCapabilitiesUI.AssistantCapabilitiesToolbarView", (IMP)hookedCapsLayout, &origCapsLayout);
        hookLayout(@"BoostCommandBar.ToolbarView", (IMP)hookedToolbarLayout, &origToolbarLayout);
        Class hoverAction = NSClassFromString(@"TabUI.TabPopoverActionButton");
        if (hoverAction) {
            origActionSetToolTip = (void *)ADHook(hoverAction, @selector(setToolTip:), (IMP)hookedActionSetToolTip);
            origActionMoveToWindow = (void *)ADHook(hoverAction, @selector(viewDidMoveToWindow), (IMP)hookedActionMoveToWindow);
        }
        Class sugg = NSClassFromString(@"BoostCommandBar.SuggestionsView");
        if (sugg) origSuggestionsSetFrame = (void *)ADHook(sugg, @selector(setFrame:), (IMP)hookedSuggestionsSetFrame);
        Class panel = NSClassFromString(@"AssistantPanelUIBase.AssistantPanelRootView");
        if (panel) origPanelSetFrame = (void *)ADHook(panel, @selector(setFrame:), (IMP)hookedPanelSetFrame);
        Class editorText = ADFindClass(@"_TtCC15BoostCommandBar17TextContainerView", @"TextView");
        if (editorText) origPlaceholderGetter = (void *)ADHook(editorText, @selector(placeholderAttributedString), (IMP)hookedPlaceholderGetter);
        applyDefaults();
        applyMenus();
        [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil
                                                    usingBlock:^(__unused NSNotification *n) { applyMenus(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:ADSettingsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(__unused NSNotification *n) {
            applyDefaults();
            applyMenus();
            relayoutWindows();
        }];
        // Dia rebuilds menus now and then; keep them in line.
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(__unused NSTimer *t) { applyMenus(); }];
        t.tolerance = 5;
    });
}
