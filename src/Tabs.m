// Tidies the sidebar's tabs: sort by domain, group by domain. Uses the tab-group calls
// Dia's sidebar answers for Chromium (ArcBrowserDelegate): there is no call to move a
// tab, but grouping tabs lays them out in the order given, and ungrouping leaves them
// there, so sorting is "group in order, then ungroup".
//
// Web contents are tracked as Dia creates or restores them (with the ArcBrowser that
// owns them); scripting supplies which tabs belong to the active profile and are pinned.
#import "Common.h"
#import <objc/message.h>

static NSMapTable *gDelegates;   // ArcBrowser -> its delegate
static NSMapTable *gOwners;      // ArcWebContents -> ArcBrowser

static void (*origSetDelegate)(id, SEL, id);
static void hookedSetDelegate(id self, SEL _cmd, id delegate) {
    [gDelegates setObject:delegate forKey:self];
    origSetDelegate(self, _cmd, delegate);
}

static void (*origTakeOwnership)(id, SEL, id);
static void hookedTakeOwnership(id self, SEL _cmd, id webContents) {
    if (webContents) [gOwners setObject:self forKey:webContents];
    origTakeOwnership(self, _cmd, webContents);
}

static id (*origCreateWebContents)(id, SEL, id);
static id hookedCreateWebContents(id self, SEL _cmd, id params) {
    id webContents = origCreateWebContents(self, _cmd, params);
    if (webContents) [gOwners setObject:self forKey:webContents];
    return webContents;
}

static void (*origDidCreate)(id, SEL, id, id, BOOL);
static void hookedDidCreate(id self, SEL _cmd, id browser, id webContents, BOOL active) {
    if (browser && webContents) [gOwners setObject:browser forKey:webContents];
    origDidCreate(self, _cmd, browser, webContents, active);
}

static void (*origDidRestore)(id, SEL, id, id, id);
static void hookedDidRestore(id self, SEL _cmd, id browser, id webContents, id sessionId) {
    if (browser && webContents) [gOwners setObject:browser forKey:webContents];
    origDidRestore(self, _cmd, browser, webContents, sessionId);
}

void TweakTabsInstall(void) {
    gDelegates = [NSMapTable weakToWeakObjectsMapTable];
    gOwners = [NSMapTable weakToWeakObjectsMapTable];
    Class browser = NSClassFromString(@"ArcBrowser"), chromium = NSClassFromString(@"ADK.ChromiumBrowser");
    if (!browser || !chromium) { NSLog(@"[daypatch] ArcBrowser not found; tab sorting inactive"); return; }
    origSetDelegate = (void *)TweakHook(browser, @selector(setDelegate:), (IMP)hookedSetDelegate);
    origTakeOwnership = (void *)TweakHook(browser, @selector(takeOwnershipOfWebContents:), (IMP)hookedTakeOwnership);
    origCreateWebContents = (void *)TweakHook(browser, @selector(createWebContents:), (IMP)hookedCreateWebContents);
    origDidCreate = (void *)TweakHook(chromium, @selector(browser:didCreateNewWebContents:isActive:), (IMP)hookedDidCreate);
    origDidRestore = (void *)TweakHook(chromium, @selector(browser:didRestoreWebContents:withSessionId:), (IMP)hookedDidRestore);
}

BOOL TweakTabsAvailable(void) {
    return origSetDelegate && origDidCreate && origDidRestore &&
        [NSClassFromString(@"ADK.ChromiumBrowser") instancesRespondToSelector:@selector(browser:createTabGroupWithSessionIds:properties:completion:)];
}

#pragma mark - Model

@interface TweakTab : NSObject
@property (nonatomic, strong) NSNumber *sessionId;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *host;
@end
@implementation TweakTab
@end

static NSString *urlString(id url) {
    if ([url isKindOfClass:NSURL.class]) return [url absoluteString];
    return [url isKindOfClass:NSString.class] ? url : nil;
}

// The site: "help.github.com" and "github.com" are both "github.com"; keeps one more
// label for two-letter country domains like "bbc.co.uk".
static NSString *hostOf(NSString *url) {
    NSString *h = [NSURL URLWithString:url].host.lowercaseString ?: @"";
    NSArray *labels = [h componentsSeparatedByString:@"."];
    if (labels.count < 3 || [h rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return h;
    NSUInteger keep = 2;
    NSString *tld = labels.lastObject, *second = labels[labels.count - 2];
    if (tld.length == 2 && [@[@"co", @"com", @"org", @"net", @"ac", @"gov", @"edu"] containsObject:second]) keep = 3;
    return [[labels subarrayWithRange:NSMakeRange(labels.count - MIN(keep, labels.count), MIN(keep, labels.count))] componentsJoinedByString:@"."];
}

typedef void (^TweakTabsBlock)(id browser, id delegate, NSArray<TweakTab *> *loose);

// The window's loose tabs (not pinned, not in a group) in the active profile, per
// owning browser, then `body` on the main queue.
static void withLooseTabs(NSWindow *window, TweakTabsBlock body) {
    // Scripting lists the active profile's tabs: count their unpinned URLs.
    NSCountedSet *wanted = [NSCountedSet set];
    @try {
        for (id sw in [NSApp valueForKey:@"appleScriptWindows"]) {
            if (![[sw valueForKey:@"windowId"] isEqual:window.identifier]) continue;
            for (id t in [sw valueForKey:@"appleScriptTabs"]) {
                NSString *url = urlString([t valueForKey:@"URL"]);
                if (url && ![[t valueForKey:@"isPinned"] boolValue]) [wanted addObject:url];
            }
        }
    } @catch (__unused NSException *e) { return; }

    NSMapTable<id, NSMutableArray<TweakTab *> *> *byBrowser = [NSMapTable strongToStrongObjectsMapTable];
    for (id wc in gOwners.keyEnumerator.allObjects) {
        id browser = [gOwners objectForKey:wc];
        NSString *url = nil;
        NSInteger sid = -1;
        @try {
            if (![[browser valueForKey:@"windowIdentifier"] isEqual:window.identifier]) continue;
            url = urlString([wc valueForKey:@"url"]);
            sid = ((NSInteger (*)(id, SEL))objc_msgSend)([wc valueForKey:@"sessionId"], @selector(identifier));
        } @catch (__unused NSException *e) { continue; }
        if (!url || sid < 0 || ![wanted countForObject:url]) continue;
        [wanted removeObject:url];
        TweakTab *t = [TweakTab new];
        t.sessionId = @(sid);
        t.url = url;
        t.host = hostOf(url);
        NSMutableArray *list = [byBrowser objectForKey:browser] ?: [NSMutableArray array];
        [list addObject:t];
        [byBrowser setObject:list forKey:browser];
    }

    for (id browser in byBrowser) {
        id delegate = [gDelegates objectForKey:browser];
        if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) continue;
        NSArray *tabs = [byBrowser objectForKey:browser];
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
            NSMutableSet *grouped = [NSMutableSet set];
            for (id g in groups) [grouped addObjectsFromArray:[g valueForKey:@"tabSessionIds"] ?: @[]];
            NSArray *loose = [tabs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TweakTab *t, id b) { return ![grouped containsObject:t.sessionId]; }]];
            dispatch_async(dispatch_get_main_queue(), ^{ body(browser, delegate, loose); });
        });
    }
}

static NSArray *sessionIds(NSArray<TweakTab *> *tabs) { return [tabs valueForKey:@"sessionId"]; }

static void createGroup(id browser, id delegate, NSArray<TweakTab *> *tabs, NSString *title, dispatch_block_t done) {
    id props = [NSClassFromString(@"ArcTabGroupProperties") new];
    [props setValue:title forKey:@"title"];
    ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(delegate, @selector(browser:createTabGroupWithSessionIds:properties:completion:),
        browser, sessionIds(tabs), props, ^(__unused id result) { dispatch_async(dispatch_get_main_queue(), done); });
}

#pragma mark - Actions

void TweakTabsSortByDomain(NSWindow *window) {
    withLooseTabs(window, ^(id browser, id delegate, NSArray<TweakTab *> *loose) {
        if (loose.count < 2) return;
        NSArray *sorted = [loose sortedArrayUsingComparator:^NSComparisonResult(TweakTab *a, TweakTab *b) {
            NSComparisonResult r = [a.host localizedStandardCompare:b.host];
            return r != NSOrderedSame ? r : [a.url localizedStandardCompare:b.url];
        }];
        createGroup(browser, delegate, sorted, @"", ^{
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(delegate, @selector(browser:removeTabsFromGroupWithSessionIds:completion:),
                browser, sessionIds(sorted), ^(__unused id result) {});
        });
    });
}

void TweakTabsGroupByDomain(NSWindow *window) {
    withLooseTabs(window, ^(id browser, id delegate, NSArray<TweakTab *> *loose) {
        NSMutableDictionary<NSString *, NSMutableArray<TweakTab *> *> *byHost = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *order = [NSMutableArray array];   // first appearance, top to bottom
        for (TweakTab *t in loose) {
            if (!t.host.length) continue;
            if (!byHost[t.host]) { byHost[t.host] = [NSMutableArray array]; [order addObject:t.host]; }
            [byHost[t.host] addObject:t];
        }
        // One at a time: Dia applies group changes in order.
        __block void (^next)(NSUInteger);
        void (^step)(NSUInteger) = ^(NSUInteger i) {
            while (i < order.count && byHost[order[i]].count < 2) i++;
            if (i >= order.count) { next = nil; return; }
            createGroup(browser, delegate, byHost[order[i]], order[i], ^{ next(i + 1); });
        };
        next = step;
        next(0);
    });
}
