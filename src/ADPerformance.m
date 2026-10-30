// Performance: turns off Dia's on-device AI service and exposes a few Chromium
// switches. Chromium switches are read once at launch.
#import "ADCommon.h"
#import <objc/runtime.h>

NSString *const ADKeyDisableOnDeviceAI = @"daypatch.disableOnDeviceAI";
NSString *const ADKeyNoBackgroundNetworking = @"daypatch.noBackgroundNetworking";
NSString *const ADKeyRendererLimit = @"daypatch.rendererProcessLimit";   // 0 = Chromium default

#pragma mark - On-device AI

// ArcAIService fronts the ai.mojom.AIService utility process. With AI hidden its
// only remaining use is classifying every string typed into the URL editor, so
// never start it.
static BOOL onDeviceAIOff(void) {
    return [ADSettings boolForKey:ADKeyHideAI] && [ADSettings boolForKey:ADKeyDisableOnDeviceAI];
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

NSArray<NSString *> *ADPerformanceSwitches(void) {
    NSMutableArray *s = [NSMutableArray array];
    if ([ADSettings boolForKey:ADKeyNoBackgroundNetworking]) [s addObject:@"--disable-background-networking"];
    NSInteger limit = [NSUserDefaults.standardUserDefaults integerForKey:ADKeyRendererLimit];
    if (limit > 0) [s addObject:[NSString stringWithFormat:@"--renderer-process-limit=%ld", (long)limit]];
    return s;
}

void ADPerformanceInstall(void) {
    Class ai = NSClassFromString(@"ArcAIService");
    if (ai) {
        origAIInitialize = (void *)ADHook(ai, @selector(initialize:callback:), (IMP)hookedAIInitialize);
        origAIIsAvailable = (void *)ADHook(ai, @selector(isAvailable), (IMP)hookedAIIsAvailable);
    } else {
        NSLog(@"[daypatch] ArcAIService not found; on-device AI switch inactive");
    }
}
