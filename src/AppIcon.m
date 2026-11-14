// Dia icon choices: the .icns pack copied into Dia at patch time.
//
// The selection lives in Application Support so DayPatch and Dia see the same
// value, and the running browser can change its Dock icon without a relaunch.
#import "Common.h"

static NSString *const kAppIconChanged = @"dev.ta3.daypatch.appIconChanged";
static NSImage *gDefaultIcon;
static NSArray<NSDictionary *> *gChoices;
static NSMutableDictionary<NSString *, NSImage *> *gImages;

static NSString *supportDir(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/daypatch"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *iconsDir(void) {
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"daypatch-icons" ofType:nil];
    if (bundled.length) return bundled;
    return [supportDir() stringByAppendingPathComponent:@"icons"];
}

static NSString *selectionPath(void) {
    return [supportDir() stringByAppendingPathComponent:@"app-icon.id"];
}

static NSString *humanize(NSString *s) {
    return [[s.stringByDeletingPathExtension stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
}

static NSArray<NSDictionary *> *manifest(void) {
    if (gChoices) return gChoices;
    NSString *path = [iconsDir() stringByAppendingPathComponent:@"icons.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSMutableArray *out = [NSMutableArray array];
    if ([json isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)json) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *ident = item[@"id"], *name = item[@"name"], *file = item[@"file"];
            if (![ident isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class] ||
                ![file isKindOfClass:NSString.class]) continue;
            if (![[NSFileManager defaultManager] fileExistsAtPath:[iconsDir() stringByAppendingPathComponent:file]]) continue;
            [out addObject:@{@"id": ident, @"name": name, @"file": file}];
        }
    }
    if (!out.count) {
        // No manifest: use whatever .icns files were copied in.
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:iconsDir() error:nil];
        for (NSString *file in [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
            if ([file.pathExtension.lowercaseString isEqualToString:@"icns"])
                [out addObject:@{@"id": file.stringByDeletingPathExtension, @"name": humanize(file), @"file": file}];
    }
    gChoices = out;
    return gChoices;
}

NSArray<NSDictionary *> *TweakAppIconChoices(void) {
    return manifest();
}

NSImage *TweakAppIconImage(NSString *iconID) {
    if (!iconID.length) return nil;
    if (gImages[iconID]) return gImages[iconID];
    for (NSDictionary *item in manifest()) {
        if (![item[@"id"] isEqualToString:iconID]) continue;
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:[iconsDir() stringByAppendingPathComponent:item[@"file"]]];
        if (image) {
            if (!gImages) gImages = [NSMutableDictionary dictionary];
            gImages[iconID] = image;
        }
        return image;
    }
    return nil;
}

NSImage *TweakDefaultAppIcon(void) {
    if (gDefaultIcon) return gDefaultIcon;

    // Copy the current icon out of NSApplication: the shared icon image can change
    // underneath us when applicationIconImage is set to a different icon later.
    NSImage *current = NSApp.applicationIconImage;
    if (current) {
        NSData *tiff = current.TIFFRepresentation;
        gDefaultIcon = tiff ? [[NSImage alloc] initWithData:tiff] : [current copy];
        if (gDefaultIcon) return gDefaultIcon;
    }

    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *file = info[@"CFBundleIconFile"];
    if (file.length) {
        NSString *name = file.stringByDeletingPathExtension;
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:file.pathExtension.length ? file.pathExtension : @"icns"];
        if (path.length) gDefaultIcon = [[NSImage alloc] initWithContentsOfFile:path];
    }
    return gDefaultIcon;
}

NSString *TweakCurrentAppIconID(void) {
    NSString *ident = [NSString stringWithContentsOfFile:selectionPath() encoding:NSUTF8StringEncoding error:nil];
    ident = [ident stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!ident.length) return nil;
    for (NSDictionary *item in manifest())
        if ([item[@"id"] isEqualToString:ident]) return ident;
    return nil;
}

static void applyAppIcon(void) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ applyAppIcon(); }); return; }
    NSString *ident = TweakCurrentAppIconID();
    NSImage *icon = TweakAppIconImage(ident);
    NSApp.applicationIconImage = icon ?: TweakDefaultAppIcon();
}

void TweakSetAppIconID(NSString *iconID) {
    if (iconID.length) {
        BOOL known = NO;
        for (NSDictionary *item in manifest())
            if ([item[@"id"] isEqualToString:iconID]) { known = YES; break; }
        if (!known) return;
    }
    NSString *path = selectionPath();
    if (iconID.length) [iconID writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    applyAppIcon();
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:kAppIconChanged object:nil userInfo:nil];
}

void TweakAppIconInstall(void) {
    void (^install)(void) = ^{
        (void)TweakDefaultAppIcon();
        [NSDistributedNotificationCenter.defaultCenter addObserverForName:kAppIconChanged object:nil queue:NSOperationQueue.mainQueue
                                                             usingBlock:^(__unused NSNotification *n) { applyAppIcon(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *n) { applyAppIcon(); }];
        applyAppIcon();
    };
    if ([NSThread isMainThread]) install();
    else dispatch_async(dispatch_get_main_queue(), install);
}
