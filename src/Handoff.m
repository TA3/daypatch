// Passkeys from Apple Passwords only work in Dia's own, unmodified app: Apple ties
// them to Dia's signature, which Dia ✦ can't keep. "Use Passkeys in Original Dia…"
// (in the Dia ✦ menu, so the command bar finds it too) asks DayPatch to hand off:
// Dia ✦ quits, the original Dia opens on the same profile, and DayPatch brings
// Dia ✦ back once the user is signed in.
#import "Common.h"

static NSString *const kExplainedKey = @"daypatch.handoffExplained";
static NSString *const kHandoffURL = @"daypatch://handoff";
static const NSInteger kItemTag = 0x44505048;   // 'DPPH'

@interface TweakHandoff : NSObject
@end

@implementation TweakHandoff

+ (void)start:(id)sender {
    NSURL *url = [NSURL URLWithString:kHandoffURL];
    if (![NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:url]) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"DayPatch isn't installed";
        a.informativeText = @"The handoff to the original Dia is done by the DayPatch app. Install it, then try again.";
        [a runModal];
        return;
    }
    if (![TweakSettings boolForKey:kExplainedKey]) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Use passkeys in the original Dia?";
        a.informativeText = @"Apple only lets Dia's own, unmodified app use passkeys from Apple Passwords. "
                            @"Dia ✦ will quit and the original Dia will open with your tabs. "
                            @"Sign in there, then click Back to Dia ✦.";
        [a addButtonWithTitle:@"Continue"];
        [a addButtonWithTitle:@"Cancel"];
        a.showsSuppressionButton = YES;
        a.suppressionButton.title = @"Don't ask again";
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (a.suppressionButton.state == NSControlStateValueOn) [TweakSettings setBool:YES forKey:kExplainedKey];
    }
    [NSWorkspace.sharedWorkspace openURL:url];
    // DayPatch waits for Dia ✦ to exit (Chromium locks the profile) before opening the original.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

@end

// Dia rebuilds its menus now and then; put the item back whenever it's missing.
static void addMenuItem(void) {
    NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
    if (!appMenu || [appMenu itemWithTag:kItemTag]) return;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Use Passkeys in Original Dia…" action:@selector(start:) keyEquivalent:@""];
    item.target = TweakHandoff.class;
    item.tag = kItemTag;
    NSInteger at = MIN((NSInteger)1, appMenu.numberOfItems);
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:at];
    [appMenu insertItem:item atIndex:at + 1];
}

void TweakHandoffInstall(void) {
    addMenuItem();
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { addMenuItem(); }];
}
