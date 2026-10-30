// Writes ~/Library/Application Support/daypatch/health.json at launch: which of
// Dia's internals each feature relies on are still present. The companion app
// shows this so a Dia update that breaks a feature doesn't go unnoticed.
#import "Common.h"
#import <objc/runtime.h>

#ifndef DAYPATCH_VERSION
#define DAYPATCH_VERSION "dev"
#endif

NSString *TweakPatchVersion(void) { return @DAYPATCH_VERSION; }

static BOOL hasMethod(NSString *cls, SEL sel) {
    Class c = NSClassFromString(cls);
    return c && class_getInstanceMethod(c, sel);
}

void TweakHealthWrite(void) {
    NSDictionary *checks = @{
        @"URL bar hiding": @(NSClassFromString(@"ContentPane.ContentPaneView") && NSClassFromString(@"NavigationBar.NavigationBarView")),
        @"Sidebar URL bar": @(TweakFindClass(@"_TtC10TabSidebar", @"SidebarContainerRootView") != nil),
        @"Settings pane": @(hasMethod(@"Preferences.SidebarListView", @selector(tableView:viewForTableColumn:row:))),
        @"Command bar": @([NSApp respondsToSelector:NSSelectorFromString(@"appleScriptWindows")] || [NSApp valueForKey:@"appleScriptWindows"] != nil),
        @"New tab without a tab": @(hasMethod(@"ArcWebContentsNavigationController", @selector(load:initiatorOrigin:transition:fromAddressBar:typedWithHttpScheme:))),
        @"Dia editor anchoring": @(TweakFindClass(@"_TtCC14DynamicPopover", @"RootView") != nil),
        @"Web engine blocking": @(hasMethod(@"ArcBrowserApplicationConfiguration", @selector(argv))),
        @"Hide AI features": @(NSClassFromString(@"TabSidebar.SidebarContainerFooterView") && NSClassFromString(@"BoostCommandBar.ToolbarView")),
        @"On-device AI off": @(hasMethod(@"ArcAIService", @selector(initialize:callback:))),
    };
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSDictionary *report = @{
        @"patchVersion": TweakPatchVersion(),
        @"diaVersion": info[@"CFBundleShortVersionString"] ?: @"?",
        @"diaBuild": info[@"CFBundleVersion"] ?: @"?",
        @"date": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        @"checks": checks,
    };
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/daypatch"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [json writeToFile:[dir stringByAppendingPathComponent:@"health.json"] atomically:YES];
}

// Background mode (no menu bar app): when Dia ✦ quits, kick the companion's
// launchd job so a pending patch or Dia update happens right away.
void TweakKickCompanionOnQuit(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *n) {
        NSString *agent = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/dev.ta3.daypatch.watch.plist"];
        if (![NSFileManager.defaultManager fileExistsAtPath:agent]) return;
        NSTask *t = [NSTask new];
        t.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
        t.arguments = @[@"kickstart", [NSString stringWithFormat:@"gui/%u/dev.ta3.daypatch.watch", getuid()]];
        [t launchAndReturnError:nil];
    }];
}
