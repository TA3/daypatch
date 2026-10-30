// daypatch entry point: installs all patches once AppKit is up.
#import "ADCommon.h"
#include <stdlib.h>

static void installKeyMonitor(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        NSEventModifierFlags mods = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        NSString *key = e.charactersIgnoringModifiers.lowercaseString;
        if (mods == (NSEventModifierFlagControl | NSEventModifierFlagCommand) && [key isEqualToString:@"u"]) {
            [ADSettings toggleHiding];
            return nil;
        }
        NSWindow *w = e.window ?: NSApp.keyWindow;
        BOOL native = ADCommandBarCurrentStyle() == ADCommandBarStyleNative;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"t"] && (native ? ADCommandBarShow(w, YES) : ADPaletteOpen(w)))
            return nil;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"l"] && native && ADCommandBarShow(w, NO))
            return nil;
        if (mods == NSEventModifierFlagCommand && [key isEqualToString:@"l"] &&
            ADSettings.urlBarMode == ADURLBarModeSidebar && ADSettings.cmdLFocusesSidebar &&
            ADSidebarFocusURLBar(e.window ?: NSApp.keyWindow))
            return nil;
        return e;
    }];
}

__attribute__((constructor)) static void init(void) {
    // Don't leak into Chromium helper processes.
    unsetenv("DYLD_INSERT_LIBRARIES");
    ADPrivacyPatchArgv();
    ADPrivacyInstall();  // URLSession hooks must exist before Dia creates its sessions
    ADPerformanceInstall();
    dispatch_async(dispatch_get_main_queue(), ^{
        ADNavBarInstall();
        ADSidebarInstall();
        ADPreferencesInstall();
        ADPaletteInstall();
        installKeyMonitor();
        NSLog(@"[daypatch] installed");
        ADHealthWrite();
        ADKickCompanionOnQuit();
    });
}
