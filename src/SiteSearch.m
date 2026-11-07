#import "SiteSearch.h"

@implementation TweakSiteSearch
@end

NSString *TweakFillSearchTemplate(NSString *urlTemplate, NSString *text) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+?#/"];  // "/" too: some engines put the query in the path
    // nil for a lone surrogate (lossy UTF-8 conversion returns nil too); replacing with nil would throw.
    NSString *q = [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    NSString *u = [urlTemplate stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:q];
    u = [u stringByReplacingOccurrencesOfString:@"{google:baseURL}" withString:@"https://www.google.com/"];
    // Drop the remaining Chromium-only placeholders ({google:RLZ} etc.).
    NSRegularExpression *ph = [NSRegularExpression regularExpressionWithPattern:@"\\{[^}]*\\}" options:0 error:nil];
    u = [ph stringByReplacingMatchesInString:u options:0 range:NSMakeRange(0, u.length) withTemplate:@""];
    while ([u hasSuffix:@"&"]) u = [u substringToIndex:u.length - 1];
    return u;
}

static NSString *withoutWWW(NSString *host) {
    return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host ?: @"";
}

// Same site and path means the same search, whatever keyword each list gives it.
static NSString *engineKey(TweakSiteSearch *e) {
    NSURL *u = [NSURL URLWithString:TweakFillSearchTemplate(e.urlTemplate, @"x")];
    return [withoutWWW(u.host.lowercaseString) stringByAppendingString:u.path ?: @""];
}

static TweakSiteSearch *makeEngine(NSString *name, NSString *keyword, NSString *urlTemplate) {
    TweakSiteSearch *e = [TweakSiteSearch new];
    e.name = name;
    e.keyword = keyword;
    e.urlTemplate = urlTemplate;
    NSURL *u = [NSURL URLWithString:TweakFillSearchTemplate(urlTemplate, @"x")];
    e.siteURL = [NSString stringWithFormat:@"%@://%@/", u.scheme ?: @"https", u.host ?: keyword];
    return e;
}

NSArray<TweakSiteSearch *> *TweakMergeSiteSearches(NSArray<NSArray<NSString *> *> *rows) {
    // Arc 1.170's seeded site searches: name, keyword, URL, pill color. Its keyword is the site's host.
    NSArray<NSArray<NSString *> *> *seeds = @[
        @[@"Google Drive", @"drive.google.com", @"https://drive.google.com/drive/search?q={searchTerms}", @"0F9D58"],
        @[@"Gmail", @"mail.google.com", @"https://mail.google.com/mail/ca/u/0/#apps/{searchTerms}", @"D44638"],
        @[@"Google Maps", @"maps.google.com", @"https://www.google.com/maps/search/{searchTerms}", @"FBBC05"],
        @[@"Google Calendar", @"calendar.google.com", @"https://calendar.google.com/calendar/u/0/r/search?q={searchTerms}", @"9C27B0"],
        @[@"Google Docs", @"docs.google.com", @"https://docs.google.com/document/u/0/?q={searchTerms}", @"4285F4"],
        @[@"Dropbox", @"dropbox.com", @"https://www.dropbox.com/search/personal?&query={searchTerms}", @"007EE5"],
        @[@"Amazon", @"amazon.com", @"https://www.amazon.com/s?k={searchTerms}", @"FF9900"],
        @[@"GitHub", @"github.com", @"https://github.com/search?q={searchTerms}", @"743FC7"],
        @[@"Figma", @"figma.com", @"https://www.figma.com/files/search?q={searchTerms}", @"F24E1E"],
        @[@"X", @"x.com", @"https://x.com/search?q={searchTerms}", @"000000"],
        @[@"Twitter", @"twitter.com", @"https://twitter.com/search?q={searchTerms}", @"000000"],
        @[@"YouTube", @"youtube.com", @"https://www.youtube.com/results?search_query={searchTerms}", @"FF0000"],
        @[@"Wikipedia", @"wikipedia.org", @"https://wikipedia.org/w/index.php?search={searchTerms}", @"FF4500"],
        @[@"Reddit", @"reddit.com", @"https://www.reddit.com/search/?q={searchTerms}", @"FF4500"],
        @[@"SoundCloud", @"soundcloud.com", @"https://soundcloud.com/search?q={searchTerms}", @"F85216"],
        @[@"Asana", @"asana.com", @"https://app.asana.com/0/search?q={searchTerms}", @"F06A6A"],
        @[@"LinkedIn", @"linkedin.com", @"https://linkedin.com/search/results/all/?keywords={searchTerms}", @"0B66C2"],
        @[@"Apple Music", @"music.apple.com", @"https://music.apple.com/us/search?term={searchTerms}", @"FA2A44"],
        @[@"Spotify", @"spotify.com", @"https://open.spotify.com/search/{searchTerms}", @"1DB954"],
    ];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableDictionary<NSString *, TweakSiteSearch *> *byKey = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *r in rows) {
        TweakSiteSearch *e = makeEngine(r[0], r[1], r[2]);
        byKey[engineKey(e)] = e;
        [out addObject:e];
    }
    for (NSArray<NSString *> *s in seeds) {
        TweakSiteSearch *e = makeEngine(s[0], s[1], s[2]);
        TweakSiteSearch *own = byKey[engineKey(e)];
        if (own) { own.colorHex = s[3]; continue; }
        e.colorHex = s[3];
        [out addObject:e];
    }
    return out;
}

TweakSiteSearch *TweakMatchSiteSearch(NSString *typed, NSArray<TweakSiteSearch *> *engines) {
    NSString *t = typed.lowercaseString;
    if (!t.length || [t rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
    for (TweakSiteSearch *e in engines) if ([e.keyword.lowercaseString isEqualToString:t]) return e;
    for (TweakSiteSearch *e in engines) {
        // "redd" must find a keyword like "red" by its site, so the host counts as well.
        NSString *host = withoutWWW([NSURL URLWithString:e.siteURL].host.lowercaseString);
        if ([e.keyword.lowercaseString hasPrefix:t] || [host hasPrefix:t]) return e;
    }
    for (TweakSiteSearch *e in engines) if ([e.name.lowercaseString hasPrefix:t]) return e;
    return nil;
}
