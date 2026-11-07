// Site Search matching and URLs. Built and run by tests/run.sh.
#import "../src/SiteSearch.h"
#include <assert.h>

int main(void) {
    NSArray *dia = @[@[@"Reddit", @"red", @"https://www.reddit.com/search/?q={searchTerms}"],
                     @[@"YouTube", @"you", @"https://www.youtube.com/results?search_query={searchTerms}"],
                     @[@"Amazon", @"ama", @"https://www.amazon.in/s?k={searchTerms}"],
                     @[@"Google", @"google.com", @"{google:baseURL}search?q={searchTerms}&{google:RLZ}"],
                     @[@"Google Maps", @"maps.google.com", @"https://www.google.com/maps/search/{searchTerms}?hl=en"]];
    NSArray *engines = TweakMergeSiteSearches(dia);
    #define MATCH(typed) TweakMatchSiteSearch(typed, engines).name

    assert([MATCH(@"redd") isEqualToString:@"Reddit"]);   // the host counts, not only the keyword "red"
    assert([MATCH(@"RED") isEqualToString:@"Reddit"]);
    assert([MATCH(@"you") isEqualToString:@"YouTube"]);
    assert([TweakMatchSiteSearch(@"ama", engines).urlTemplate containsString:@"amazon.in"]);  // Dia's own engine beats Arc's
    assert([MATCH(@"git") isEqualToString:@"GitHub"]);    // only in Arc's list
    assert([MATCH(@"go") isEqualToString:@"Google"]);
    assert([MATCH(@"maps") isEqualToString:@"Google Maps"]);
    assert([MATCH(@"x") isEqualToString:@"X"]);
    assert(!MATCH(@""));
    assert(!MATCH(@"red dit"));
    assert(!MATCH(@"zzz"));

    NSUInteger reddits = 0;
    for (TweakSiteSearch *e in engines) if ([e.name isEqualToString:@"Reddit"]) { reddits++; assert([e.colorHex isEqualToString:@"FF4500"]); }
    assert(reddits == 1);  // one list's Reddit, colored from Arc's

    assert([TweakFillSearchTemplate(@"https://www.reddit.com/search/?q={searchTerms}", @"cats & dogs") isEqualToString:@"https://www.reddit.com/search/?q=cats%20%26%20dogs"]);
    assert([TweakFillSearchTemplate(@"https://open.spotify.com/search/{searchTerms}", @"ac/dc") isEqualToString:@"https://open.spotify.com/search/ac%2Fdc"]);
    assert([TweakFillSearchTemplate(@"{google:baseURL}search?q={searchTerms}&{google:RLZ}", @"x") isEqualToString:@"https://www.google.com/search?q=x"]);
    return 0;
}
