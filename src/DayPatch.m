// daypatch entry point: installs all patches once AppKit is up.
#import "Common.h"
#include <stdlib.h>

static void installKeyMonitor(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        NSEventModifierFlags mods = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        NSString *key = e.charactersIgnoringModifiers.lowercaseString;
        if (mods == (NSEventModifierFlagControl | NSEventModifierFlagCommand) && [key isEqualToString:@"u"]) {
            [TweakSettings toggleHiding];
            return nil;
        }
        NSWindow *w = e.window ?: NSApp.keyWindow;
        BOOL native = TweakCommandBarCurrentStyle() == TweakCommandBarStyleNative;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"t"] && (native ? TweakCommandBarShow(w, YES) : TweakPaletteOpen(w)))
            return nil;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"l"] && native && TweakCommandBarShow(w, NO))
            return nil;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"l"] &&
            TweakSettings.urlBarMode == TweakURLBarModeSidebar && TweakSettings.cmdLFocusesSidebar &&
            TweakSidebarFocusURLBar(e.window ?: NSApp.keyWindow))
            return nil;
        return e;
    }];
}

__attribute__((constructor)) static void init(void) {
    // Don't leak into Chromium helper processes.
    unsetenv("DYLD_INSERT_LIBRARIES");
    TweakPrivacyPatchArgv();
    TweakPrivacyInstall();  // URLSession hooks must exist before Dia creates its sessions
    TweakPerformanceInstall();
    dispatch_async(dispatch_get_main_queue(), ^{
        TweakNavBarInstall();
        TweakSidebarInstall();
        TweakPreferencesInstall();
        TweakPaletteInstall();
        installKeyMonitor();
        NSLog(@"[daypatch] installed");
        TweakHealthWrite();
        TweakKickCompanionOnQuit();
    });
}
