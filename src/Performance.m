// Performance: turns off Dia's on-device AI service and exposes a few Chromium
// switches. Chromium switches are read once at launch.
#import "Common.h"
#import <objc/runtime.h>

NSString *const TweakKeyDisableOnDeviceAI = @"daypatch.disableOnDeviceAI";
NSString *const TweakKeyNoBackgroundNetworking = @"daypatch.noBackgroundNetworking";
NSString *const TweakKeyRendererLimit = @"daypatch.rendererProcessLimit";   // 0 = Chromium default

#pragma mark - On-device AI

// ArcAIService fronts the ai.mojom.AIService utility process. With AI hidden its
// only remaining use is classifying every string typed into the URL editor, so
// never start it.
static BOOL onDeviceAIOff(void) {
    return [TweakSettings boolForKey:TweakKeyHideAI] && [TweakSettings boolForKey:TweakKeyDisableOnDeviceAI];
}

static void (*origAIInitialize)(id, SEL, id, id);
static void hookedAIInitialize(id self, SEL _cmd, id config, id callback) {
    if (onDeviceAIOff()) { NSLog(@"[daypatch] on-device AI service not started"); return; }
    origAIInitialize(self, _cmd, config, callback);
}

static BOOL (*origAIIsAvailable)(id, SEL);
static BOOL hookedAIIsAvailable(id self, SEL _cmd) {
    return onDeviceAIOff() ? NO : origAIIsAvailable(self, _cmd);
}

#pragma mark - Chromium switches

NSArray<NSString *> *TweakPerformanceSwitches(void) {
    NSMutableArray *s = [NSMutableArray array];
    if ([TweakSettings boolForKey:TweakKeyNoBackgroundNetworking]) [s addObject:@"--disable-background-networking"];
    NSInteger limit = [NSUserDefaults.standardUserDefaults integerForKey:TweakKeyRendererLimit];
    if (limit > 0) [s addObject:[NSString stringWithFormat:@"--renderer-process-limit=%ld", (long)limit]];
    return s;
}

void TweakPerformanceInstall(void) {
    Class ai = NSClassFromString(@"ArcAIService");
    if (ai) {
        origAIInitialize = (void *)TweakHook(ai, @selector(initialize:callback:), (IMP)hookedAIInitialize);
        origAIIsAvailable = (void *)TweakHook(ai, @selector(isAvailable), (IMP)hookedAIIsAvailable);
    } else {
        NSLog(@"[daypatch] ArcAIService not found; on-device AI switch inactive");
    }
}
