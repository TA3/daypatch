#import "ADCommandSources.h"
#import "ADCommon.h"
#include <sqlite3.h>

@implementation ADItem
@end

static NSString *profileDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/Default"];
}

#pragma mark - Matching

// Scores how well `query` matches an item: every word must appear in the title or
// URL; word-prefix and host-prefix hits count more than mid-word hits.
static double matchScore(NSArray<NSString *> *words, NSString *title, NSString *url) {
    NSString *t = title.lowercaseString ?: @"";
    NSString *u = url.lowercaseString ?: @"";
    NSString *host = [NSURL URLWithString:url].host.lowercaseString ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    double score = 0;
    for (NSString *w in words) {
        double best = 0;
        if ([host hasPrefix:w]) best = 4;
        else if ([t hasPrefix:w]) best = 4;
        else if ([t rangeOfString:[@" " stringByAppendingString:w]].location != NSNotFound) best = 3;
        else if ([t containsString:w]) best = 1.5;
        else if ([host containsString:w]) best = 1.5;
        else if ([u containsString:w]) best = 0.8;
        if (best == 0) return 0;
        score += best;
    }
    // A title that is exactly what's typed, or starts with it, wins outright.
    NSString *q = [words componentsJoinedByString:@" "];
    if ([t isEqualToString:q]) score += 4;
    else if ([t hasPrefix:q]) score += 2;
    return score;
}

static BOOL looksLikeURL(NSString *s) {
    if ([s rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) return NO;
    if ([s containsString:@"://"] || [s hasPrefix:@"about:"] || [s hasPrefix:@"localhost"]) return YES;
    NSString *host = [s componentsSeparatedByString:@"/"].firstObject;
    NSRange dot = [host rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location != NSNotFound && dot.location > 0 && host.length - dot.location - 1 >= 2;
}

NSString *ADShortcutString(NSMenuItem *item) {
    if (!item.keyEquivalent.length) return @"";
    NSMutableString *s = [NSMutableString string];
    NSEventModifierFlags m = item.keyEquivalentModifierMask;
    if (m & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (m & NSEventModifierFlagOption) [s appendString:@"⌥"];
    if (m & NSEventModifierFlagShift) [s appendString:@"⇧"];
    if (m & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    NSString *k = item.keyEquivalent;
    NSDictionary *names = @{@"\r": @"↩", @"\t": @"⇥", @" ": @"Space", @"\x1b": @"⎋", @"\x7f": @"⌫",
                            [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey]: @"←",
                            [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey]: @"→",
                            [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]: @"↑",
                            [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey]: @"↓"};
    [s appendString:names[k] ?: k.uppercaseString];
    return s;
}

#pragma mark - Sources

@implementation ADCommandSources {
    NSArray<ADItem *> *_commands;
    NSArray<ADItem *> *_pages;
    NSArray<ADItem *> *_tabs;
    NSArray<ADItem *> *_bookmarks;
    NSString *_searchTemplate;
    NSString *_activeURL;
    dispatch_queue_t _queue;
    NSUInteger _generation;
    NSCache<NSString *, id> *_icons;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("daypatch.history", DISPATCH_QUEUE_SERIAL);
        _icons = [NSCache new];
    }
    return self;
}

- (void)prepareForWindow:(NSWindow *)window {
    _commands = [self loadCommands];
    _pages = [self loadPages];
    _tabs = [self loadTabs];
    if (!_bookmarks) _bookmarks = [self loadBookmarks];
    if (!_searchTemplate) _searchTemplate = [self loadSearchTemplate];
    _activeURL = ADURLForWindow(window);
}

// Every enabled, visible command in Dia's menus, including submenus.
- (NSArray<ADItem *> *)loadCommands {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSSet *skipMenus = [NSSet setWithArray:@[@"Services", @"Open Recent", @"Help"]];
    __block void (^walk)(NSMenu *, NSString *) = nil;
    void (^__block __weak weakWalk)(NSMenu *, NSString *);
    NSSet *topTitles = [NSSet setWithArray:[NSApp.mainMenu.itemArray valueForKey:@"title"]];
    weakWalk = walk = ^(NSMenu *menu, NSString *path) {
        [menu update];  // runs Dia's validation so isEnabled is current
        for (NSMenuItem *i in menu.itemArray) {
            if (i.isSeparatorItem || i.isHidden || !i.title.length) continue;
            if (i.submenu) {
                if (![skipMenus containsObject:i.title]) weakWalk(i.submenu, i.title);
                continue;
            }
            if (!i.action || !i.isEnabled) continue;
            if (i.action == @selector(makeKeyAndOrderFront:)) continue;  // window list
            NSString *title = [i.title stringByReplacingOccurrencesOfString:@"…" withString:@""];
            if (![topTitles containsObject:path]) title = [NSString stringWithFormat:@"%@ › %@", path, title];
            if ([seen containsObject:title]) continue;
            [seen addObject:title];
            ADItem *it = [ADItem new];
            it.kind = ADItemCommand;
            it.title = title;
            it.detail = ADShortcutString(i);
            it.menuItem = i;
            it.symbol = [self symbolForCommand:title];
            [out addObject:it];
        }
    };
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        if (top.submenu) walk(top.submenu, top.title);
    walk = nil;
    return out;
}

- (NSString *)symbolForCommand:(NSString *)t {
    NSDictionary *map = @{@"Settings": @"gearshape", @"New Window": @"macwindow.badge.plus", @"New Tab": @"plus.square",
                          @"Close Tab": @"xmark.square", @"Reopen Closed Tab": @"arrow.uturn.backward.square",
                          @"Print": @"printer", @"Copy URL": @"link", @"Find": @"magnifyingglass", @"Reload": @"arrow.clockwise",
                          @"Downloads": @"arrow.down.circle", @"History": @"clock", @"Bookmarks": @"bookmark",
                          @"Extensions": @"puzzlepiece.extension", @"Quit Dia": @"power", @"Zoom In": @"plus.magnifyingglass",
                          @"Zoom Out": @"minus.magnifyingglass", @"Developer Tools": @"hammer", @"Task Manager": @"chart.bar"};
    for (NSString *k in map) if ([t hasPrefix:k]) return map[k];
    return @"command";
}

- (NSArray<ADItem *> *)loadPages {
    NSArray *pages = @[
        @[@"Chrome Flags", @"chrome://flags", @"flag"],
        @[@"Extensions", @"chrome://extensions", @"puzzlepiece.extension"],
        @[@"Downloads", @"chrome://downloads", @"arrow.down.circle"],
        @[@"History", @"chrome://history", @"clock"],
        @[@"Bookmarks", @"chrome://bookmarks", @"bookmark"],
        @[@"Passwords", @"chrome://password-manager", @"key"],
        @[@"Clear Browsing Data", @"chrome://settings/clearBrowserData", @"trash"],
        @[@"Privacy and Security", @"chrome://settings/privacy", @"hand.raised"],
        @[@"Site Settings", @"chrome://settings/content", @"slider.horizontal.3"],
        @[@"Cookies and Site Data", @"chrome://settings/cookies", @"circle.hexagongrid"],
        @[@"Search Engines", @"chrome://settings/searchEngines", @"magnifyingglass"],
        @[@"Autofill and Addresses", @"chrome://settings/addresses", @"person.text.rectangle"],
        @[@"Payment Methods", @"chrome://settings/payments", @"creditcard"],
        @[@"Version", @"chrome://version", @"info.circle"],
        @[@"GPU", @"chrome://gpu", @"cpu"],
        @[@"Inspect Devices", @"chrome://inspect", @"hammer"],
        @[@"Net Internals", @"chrome://net-internals", @"network"],
    ];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *p in pages) {
        ADItem *it = [ADItem new];
        it.kind = ADItemPage;
        it.title = p[0];
        it.url = p[1];
        it.detail = p[1];
        it.symbol = p[2];
        [out addObject:it];
    }
    return out;
}

- (NSArray<ADItem *> *)loadTabs {
    NSMutableArray *out = [NSMutableArray array];
    @try {
        for (id sw in [NSApp valueForKey:@"appleScriptWindows"]) {
            NSString *wid = [sw valueForKey:@"windowId"];
            for (id tab in [sw valueForKey:@"appleScriptTabs"]) {
                NSString *url = [tab valueForKey:@"URL"];
                if (![url isKindOfClass:NSString.class] || !url.length || [url hasPrefix:@"dia://"]) continue;
                ADItem *it = [ADItem new];
                it.kind = ADItemTab;
                it.title = [tab valueForKey:@"title"] ?: url;
                it.url = url;
                it.detail = @"Switch to Tab";
                it.tabId = [tab valueForKey:@"tabId"];
                it.windowId = wid;
                it.symbol = @"square.on.square";
                it.frecency = 3.0;  // open tabs are usually what you're looking for
                [out addObject:it];
            }
        }
    } @catch (__unused NSException *e) {}
    return out;
}

- (NSArray<ADItem *> *)loadBookmarks {
    NSData *data = [NSData dataWithContentsOfFile:[profileDir() stringByAppendingPathComponent:@"Bookmarks"]];
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSMutableArray *out = [NSMutableArray array];
    __block void (^walk)(NSDictionary *) = nil;
    void (^__block __weak weakWalk)(NSDictionary *);
    weakWalk = walk = ^(NSDictionary *node) {
        if ([node[@"type"] isEqual:@"url"] && [node[@"url"] isKindOfClass:NSString.class]) {
            ADItem *it = [ADItem new];
            it.kind = ADItemBookmark;
            it.title = node[@"name"];
            it.url = node[@"url"];
            it.detail = node[@"url"];
            it.symbol = @"bookmark";
            it.frecency = 1.0;
            [out addObject:it];
        }
        for (NSDictionary *c in node[@"children"]) if ([c isKindOfClass:NSDictionary.class]) weakWalk(c);
    };
    for (NSDictionary *root in [json[@"roots"] allValues]) if ([root isKindOfClass:NSDictionary.class]) walk(root);
    walk = nil;
    return out;
}

// Dia's default search engine, from the profile's Preferences + Web Data.
- (NSString *)loadSearchTemplate {
    NSString *fallback = @"https://www.google.com/search?q={searchTerms}";
    NSData *prefs = [NSData dataWithContentsOfFile:[profileDir() stringByAppendingPathComponent:@"Preferences"]];
    NSDictionary *p = prefs ? [NSJSONSerialization JSONObjectWithData:prefs options:0 error:nil] : nil;
    NSString *guid = p[@"default_search_provider"][@"guid"];
    if (![guid isKindOfClass:NSString.class]) return fallback;
    __block NSString *url = nil;
    [self sqlite:@"Web Data" query:@"SELECT url FROM keywords WHERE sync_guid = ?1 LIMIT 1" bind:@[guid] row:^(sqlite3_stmt *s) {
        url = @((const char *)sqlite3_column_text(s, 0) ?: "");
    }];
    return url.length ? url : fallback;
}

- (NSString *)searchURLFor:(NSString *)text {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+?#"];
    NSString *q = [text stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSString *u = [_searchTemplate ?: @"https://www.google.com/search?q={searchTerms}" stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:q];
    u = [u stringByReplacingOccurrencesOfString:@"{google:baseURL}" withString:@"https://www.google.com/"];
    // Drop the remaining Chromium-only placeholders ({google:RLZ} etc.).
    NSRegularExpression *ph = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:nil];
    u = [ph stringByReplacingMatchesInString:u options:0 range:NSMakeRange(0, u.length) withTemplate:@""];
    while ([u hasSuffix:@"&"]) u = [u substringToIndex:u.length - 1];
    return u;
}

- (NSString *)searchEngineName {
    NSString *host = [NSURL URLWithString:[self searchURLFor:@"x"]].host;
    for (NSString *n in @[@"Google", @"DuckDuckGo", @"Bing", @"Brave", @"Ecosia", @"Kagi", @"Perplexity", @"Startpage"])
        if ([host.lowercaseString containsString:n.lowercaseString]) return n;
    return host ?: @"the web";
}

#pragma mark - SQLite (read-only, never locks Dia's databases)

- (void)sqlite:(NSString *)file query:(NSString *)sql bind:(NSArray *)args row:(void (^)(sqlite3_stmt *))row {
    NSString *path = [profileDir() stringByAppendingPathComponent:file];
    NSString *uri = [NSString stringWithFormat:@"file:%@?immutable=1", [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(uri.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) != SQLITE_OK) { sqlite3_close(db); return; }
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK) {
        for (int i = 0; i < (int)args.count; i++) {
            if ([args[i] isKindOfClass:NSNumber.class]) sqlite3_bind_int64(st, i + 1, [args[i] longLongValue]);
            else sqlite3_bind_text(st, i + 1, [args[i] UTF8String], -1, SQLITE_TRANSIENT);
        }
        while (sqlite3_step(st) == SQLITE_ROW) row(st);
    }
    sqlite3_finalize(st);
    sqlite3_close(db);
}

static NSString *likeEscape(NSString *s) {
    return [[[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"]
            stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
}

- (NSArray<ADItem *> *)historyFor:(NSArray<NSString *> *)words {
    if (!words.count) return @[];
    // Every word must appear in the URL or title; rank by typed count, visits, recency.
    NSMutableString *where = [NSMutableString stringWithString:@"hidden = 0"];
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *w in words) {
        [args addObject:[NSString stringWithFormat:@"%%%@%%", likeEscape(w)]];
        [where appendFormat:@" AND (url LIKE ?%lu ESCAPE '\\' OR title LIKE ?%lu ESCAPE '\\')", (unsigned long)args.count, (unsigned long)args.count];
    }
    NSString *sql = [NSString stringWithFormat:@"SELECT url, title, visit_count, typed_count, last_visit_time FROM urls WHERE %@ "
                     "ORDER BY typed_count DESC, visit_count DESC, last_visit_time DESC LIMIT 60", where];
    NSMutableArray *out = [NSMutableArray array];
    // Chromium time: microseconds since 1601-01-01.
    double nowChrome = (NSDate.date.timeIntervalSince1970 + 11644473600.0) * 1e6;
    [self sqlite:@"History" query:sql bind:args row:^(sqlite3_stmt *s) {
        ADItem *it = [ADItem new];
        it.kind = ADItemHistory;
        it.url = @((const char *)sqlite3_column_text(s, 0) ?: "");
        NSString *title = @((const char *)sqlite3_column_text(s, 1) ?: "");
        it.title = title.length ? title : it.url;
        it.detail = it.url;
        it.symbol = @"globe";
        double visits = sqlite3_column_int(s, 2), typed = sqlite3_column_int(s, 3);
        double ageDays = MAX(0, (nowChrome - sqlite3_column_int64(s, 4)) / 8.64e10);
        it.frecency = MIN(3.0, log2(visits + 1) * 0.35 + typed * 0.4) + 1.5 / (1 + ageDays / 7.0);
        [out addObject:it];
    }];
    return out;
}

#pragma mark - Query

- (void)query:(NSString *)text done:(void (^)(NSArray<ADItem *> *))done {
    NSString *q = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
    NSUInteger gen = ++_generation;
    if (!q.length) {
        // Empty: open tabs, most recent first, like Arc.
        NSArray *tabs = [_tabs subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, _tabs.count))];
        done(tabs);
        return;
    }
    NSArray *words = [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSArray *commands = _commands, *pages = _pages, *tabs = _tabs, *bookmarks = _bookmarks;
    NSString *activeURL = _activeURL;
    dispatch_async(_queue, ^{
        NSMutableArray<ADItem *> *all = [NSMutableArray array];
        // Ranking: a command, page or tab that matches by prefix beats history (as in
        // Arc); history is ordered by match plus frecency.
        void (^add)(NSArray<ADItem *> *, double, double, double) = ^(NSArray<ADItem *> *list, double minMatch, double weight, double prefixBonus) {
            for (ADItem *it in list) {
                double m = matchScore(words, it.title, it.kind == ADItemCommand ? nil : it.url);
                if (m < minMatch) continue;
                // The bonus grows with how much of the title was typed: "setti" for Settings
                // earns it, "go" for "Go Back" mostly doesn't.
                double coverage = MIN(1.0, 2.0 * q.length / MAX((NSUInteger)1, it.title.length));
                it.score = m * weight + it.frecency + (m >= 4 * words.count ? prefixBonus * coverage : 0);
                [all addObject:it];
            }
        };
        add(commands, 2.5, 1.2, 4.5);
        add(pages, 2.5, 1.2, 3.0);
        add(tabs, 0.8, 1.25, 2.5);
        add(bookmarks, 1.0, 1.1, 1.0);
        add([self historyFor:words], 0.8, 1.0, 0);

        // De-duplicate URLs: an open tab beats a bookmark beats history.
        [all sortUsingComparator:^NSComparisonResult(ADItem *a, ADItem *b) { return a.score > b.score ? NSOrderedAscending : a.score < b.score ? NSOrderedDescending : NSOrderedSame; }];
        NSMutableArray<ADItem *> *ranked = [NSMutableArray array];
        NSMutableSet *urls = [NSMutableSet set];
        NSCountedSet *perSite = [NSCountedSet set], *perTitle = [NSCountedSet set];
        for (ADItem *it in all) {
            NSString *key = it.url ? [it.url stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] : it.title;
            if (it.kind == ADItemTab && [it.url isEqualToString:activeURL]) continue;  // already here
            if ([urls containsObject:key]) continue;
            // At most two history rows per site, so one site can't fill the list.
            NSString *site = [NSURL URLWithString:it.url].host;
            if (it.kind == ADItemHistory && site && [perSite countForObject:site] >= 2) continue;
            if (it.kind == ADItemHistory && it.title && [perTitle countForObject:it.title] >= 2) continue;
            if (site) [perSite addObject:site];
            if (it.title) [perTitle addObject:it.title];
            [urls addObject:key];
            [ranked addObject:it];
        }

        // What was typed: as an address, or a search. Second place unless nothing else is strong.
        ADItem *typed = [ADItem new];
        if (looksLikeURL(q)) {
            typed.kind = ADItemURL;
            typed.url = ADResolveInput(text);
            typed.title = text;
            typed.detail = @"Open";
            typed.symbol = @"globe";
        } else {
            typed.kind = ADItemSearch;
            typed.title = text;
            typed.url = [self searchURLFor:text];
            typed.detail = [@"Search " stringByAppendingString:[self searchEngineName]];
            typed.symbol = @"magnifyingglass";
        }
        BOOL strongTop = ranked.count && ((ADItem *)ranked[0]).score >= 5;
        [ranked insertObject:typed atIndex:strongTop ? 1 : 0];

        NSArray *items = [ranked subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, ranked.count))];
        dispatch_async(dispatch_get_main_queue(), ^{ if (gen == self->_generation) done(items); });
    });
}

- (NSString *)completionFor:(NSString *)text inItems:(NSArray<ADItem *> *)items {
    NSString *q = text.lowercaseString;
    if (!q.length || [q rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) return nil;
    for (ADItem *it in items) {
        if (it.kind != ADItemHistory && it.kind != ADItemTab && it.kind != ADItemBookmark) continue;
        NSString *host = [NSURL URLWithString:it.url].host.lowercaseString;
        if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
        if (host.length > q.length && [host hasPrefix:q]) return host;
        break;  // only complete from the top-ranked page
    }
    return nil;
}

#pragma mark - Favicons

- (NSImage *)faviconFor:(NSString *)url {
    if (!url.length) return nil;
    id cached = [_icons objectForKey:url];
    if (cached) return cached == NSNull.null ? nil : cached;
    __block NSData *png = nil;
    // Exact page first, then any page on the same host.
    NSString *host = [NSURL URLWithString:url].host;
    NSString *sql = @"SELECT b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id "
                     "WHERE m.page_url = ?1 OR m.page_url LIKE ?2 ORDER BY (m.page_url = ?1) DESC, b.width DESC LIMIT 1";
    [self sqlite:@"Favicons" query:sql bind:@[url, [NSString stringWithFormat:@"%%://%@/%%", host ?: @"-"]] row:^(sqlite3_stmt *s) {
        png = [NSData dataWithBytes:sqlite3_column_blob(s, 0) length:sqlite3_column_bytes(s, 0)];
    }];
    NSImage *img = png.length ? [[NSImage alloc] initWithData:png] : nil;
    [_icons setObject:img ?: (id)NSNull.null forKey:url];
    return img;
}

@end
