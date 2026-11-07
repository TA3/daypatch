// Arc-style Site Search: "redd" + Tab scopes the command bar to Reddit.
#import <Foundation/Foundation.h>

@interface TweakSiteSearch : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, copy) NSString *urlTemplate;  // Chromium's form, with {searchTerms}
@property (nonatomic, copy) NSString *siteURL;      // where its favicon is looked up
@property (nonatomic, copy) NSString *colorHex;     // Arc's pill color; nil for sites Arc doesn't seed
@end

// `urlTemplate` with `text` percent-encoded into {searchTerms} and Chromium's other placeholders resolved.
NSString *TweakFillSearchTemplate(NSString *urlTemplate, NSString *text);
// Dia's engines ([name, keyword, url] rows, which win) followed by the sites Arc seeds.
NSArray<TweakSiteSearch *> *TweakMergeSiteSearches(NSArray<NSArray<NSString *> *> *rows);
// The engine Tab enters for `typed`: exact keyword, then keyword or host prefix, then name prefix.
TweakSiteSearch *TweakMatchSiteSearch(NSString *typed, NSArray<TweakSiteSearch *> *engines);
