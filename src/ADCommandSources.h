// Result sources and ranking for the daypatch command bar.
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ADItemKind) {
    ADItemSearch,
    ADItemURL,       // what was typed, when it looks like an address
    ADItemCommand,   // a Dia menu command
    ADItemPage,      // a chrome:// page
    ADItemTab,       // an open tab
    ADItemBookmark,
    ADItemHistory,
};

@interface ADItem : NSObject
@property (nonatomic) ADItemKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;     // URL, shortcut, or "Switch to tab"
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *symbol;     // SF Symbol when there's no favicon
@property (nonatomic, strong) NSMenuItem *menuItem;
@property (nonatomic, copy) NSString *tabId;
@property (nonatomic, copy) NSString *windowId;
@property (nonatomic) double score;
@property (nonatomic) double frecency;            // history/bookmark/tab prior
@end

@interface ADCommandSources : NSObject
// Snapshot of commands, tabs, bookmarks taken when the bar opens.
- (void)prepareForWindow:(NSWindow *)window;
// Ranked results for a query. History is queried off the main thread; `done` runs on main.
- (void)query:(NSString *)text done:(void (^)(NSArray<ADItem *> *items))done;
// The host to complete inline for `text`, if any (e.g. "git" -> "github.com").
- (NSString *)completionFor:(NSString *)text inItems:(NSArray<ADItem *> *)items;
- (NSString *)searchURLFor:(NSString *)text;
- (NSImage *)faviconFor:(NSString *)url;  // cached; nil if unknown
@end

NSString *ADShortcutString(NSMenuItem *item);
