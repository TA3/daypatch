// Dev tool: dumps Dia's window/view-controller hierarchy to /tmp/dia_views.txt.
// Opens Settings first so its structure is included.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

static void dumpView(NSView *v, int depth, NSMutableString *out) {
    NSRect f = v.frame;
    NSString *extra = @"";
    if ([v isKindOfClass:NSTextField.class]) extra = [NSString stringWithFormat:@" text=\"%@\"", [(NSTextField *)v stringValue]];
    else if ([v isKindOfClass:NSButton.class]) extra = [NSString stringWithFormat:@" title=\"%@\"", [(NSButton *)v title]];
    NSString *ax = v.accessibilityLabel ?: v.accessibilityIdentifier;
    if (ax.length) extra = [extra stringByAppendingFormat:@" ax=\"%@\"", ax];
    [out appendFormat:@"%*s%@ frame=(%.0f,%.0f %.0fx%.0f)%@%@\n", depth * 2, "",
        NSStringFromClass(v.class), f.origin.x, f.origin.y, f.size.width, f.size.height,
        v.hidden ? @" HIDDEN" : @"", extra];
    for (NSView *s in v.subviews) dumpView(s, depth + 1, out);
}

static void dumpVC(NSViewController *vc, int depth, NSMutableString *out) {
    [out appendFormat:@"%*sVC %@ title=\"%@\"\n", depth * 2, "", NSStringFromClass(vc.class), vc.title];
    if ([vc isKindOfClass:NSTabViewController.class])
        for (NSTabViewItem *i in [(NSTabViewController *)vc tabViewItems])
            [out appendFormat:@"%*s  tab \"%@\" id=%@\n", depth * 2, "", i.label, i.identifier];
    for (NSViewController *c in vc.childViewControllers) dumpVC(c, depth + 1, out);
}

static void dumpAll(void) {
    NSMutableString *out = [NSMutableString string];
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        [out appendFormat:@"MENU %@\n", top.title];
        for (NSMenuItem *i in top.submenu.itemArray)
            if (!i.isSeparatorItem) [out appendFormat:@"  %@ [%@%@] action=%@\n", i.title,
                i.keyEquivalentModifierMask & NSEventModifierFlagCommand ? @"cmd+" : @"", i.keyEquivalent,
                NSStringFromSelector(i.action)];
    }
    for (NSWindow *w in NSApp.windows) {
        if (!w.isVisible) continue;
        [out appendFormat:@"=== %@ \"%@\" wc=%@\n", NSStringFromClass(w.class), w.title, NSStringFromClass(w.windowController.class)];
        if (w.toolbar) for (NSToolbarItem *t in w.toolbar.items) [out appendFormat:@"  toolbar \"%@\" id=%@\n", t.label, t.itemIdentifier];
        if (w.contentViewController) dumpVC(w.contentViewController, 1, out);
        dumpView(w.contentView.superview ?: w.contentView, 0, out);
    }
    [out writeToFile:@"/tmp/dia_views.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void findTables(NSView *v, NSMutableArray *acc) {
    if ([v isKindOfClass:NSTableView.class]) [acc addObject:v];
    for (NSView *s in v.subviews) findTables(s, acc);
}

static void dumpMethods(id obj, NSMutableString *out) {
    for (Class c = [obj class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
        unsigned n = 0;
        Method *ms = class_copyMethodList(c, &n);
        [out appendFormat:@"  class %@ (%u methods)\n", NSStringFromClass(c), n];
        for (unsigned i = 0; i < n; i++) [out appendFormat:@"    %@\n", NSStringFromSelector(method_getName(ms[i]))];
        free(ms);
    }
}

static void dumpTables(void) {
    NSMutableString *out = [NSMutableString string];
    for (NSWindow *w in NSApp.windows) {
        if (![NSStringFromClass(w.class) containsString:@"Preferences"]) continue;
        NSMutableArray *tables = [NSMutableArray array];
        findTables(w.contentView, tables);
        for (NSTableView *t in tables) {
            [out appendFormat:@"TABLE %@ rows=%ld selected=%ld style=%ld\n", NSStringFromClass(t.class), t.numberOfRows, t.selectedRow, t.style];
            [out appendFormat:@" delegate:\n"]; dumpMethods(t.delegate, out);
            if ((id)t.dataSource != (id)t.delegate) { [out appendFormat:@" dataSource:\n"]; dumpMethods(t.dataSource, out); }
            for (NSInteger r = 0; r < MIN(t.numberOfRows, 9); r++) {
                NSTableRowView *rv = [t rowViewAtRow:r makeIfNecessary:NO];
                [out appendFormat:@" row %ld %@\n", r, NSStringFromClass(rv.class)];
                if (rv) dumpView(rv, 2, out);
            }
        }
    }
    // Scripting bridge objects: how do they map to NSWindows?
    for (NSWindow *w in NSApp.windows)
        [out appendFormat:@"NSWindow %@ number=%ld identifier=%@\n", NSStringFromClass(w.class), w.windowNumber, w.identifier];
    @try {
        NSArray *sw = [NSApp valueForKey:@"appleScriptWindows"];
        for (id o in sw) {
            [out appendFormat:@"ScriptWindow %@ windowId=%@ name=%@\n", NSStringFromClass([o class]), [o valueForKey:@"windowId"], [o valueForKey:@"name"]];
            dumpMethods(o, out);
            id tab = [o valueForKey:@"activeTab"];
            [out appendFormat:@"  activeTab %@ url=%@ title=%@\n", NSStringFromClass([tab class]), [tab valueForKey:@"URL"], [tab valueForKey:@"title"]];
            dumpMethods(tab, out);
            break;
        }
    } @catch (NSException *e) { [out appendFormat:@"script err %@\n", e]; }
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *i in top.submenu.itemArray)
            if ([i.title.lowercaseString containsString:@"reload"]) [out appendFormat:@"RELOAD %@ action=%@ key=%@\n", i.title, NSStringFromSelector(i.action), i.keyEquivalent];
    [out writeToFile:@"/tmp/dia_tables.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSMenuItem *findSettingsItem(void) {
    for (NSMenuItem *i in NSApp.mainMenu.itemArray.firstObject.submenu.itemArray)
        if ([i.keyEquivalent isEqualToString:@","]) return i;
    return nil;
}

__attribute__((constructor)) static void init(void) {
    unsetenv("DYLD_INSERT_LIBRARIES");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSMenuItem *s = findSettingsItem();
        if (s) [NSApp sendAction:s.action to:s.target from:s];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ dumpAll(); dumpTables(); });
    });
}
