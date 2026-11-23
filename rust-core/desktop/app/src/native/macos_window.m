// The macOS window chrome, the reduce-motion setting and the share sheet.
//
// The window keeps its native frame with a unified, transparent toolbar title bar: the QML
// toolbar draws under it, beside the traffic lights. The share sheet offers a text (such as
// a diagnostics export) to the services the person has; no file is written.

#import <AppKit/AppKit.h>
#include <stdbool.h>

void gitlama_configure_windows(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (window.toolbar != nil || (window.styleMask & NSWindowStyleMaskTitled) == 0) {
            continue;
        }
        window.titleVisibility = NSWindowTitleHidden;
        window.titlebarAppearsTransparent = YES;
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"GitLamaWindowToolbar"];
        toolbar.showsBaselineSeparator = NO;
        window.toolbar = toolbar;
        if (@available(macOS 11.0, *)) {
            window.toolbarStyle = NSWindowToolbarStyleUnified;
            window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        }
    }
}

bool gitlama_system_reduce_motion(void) {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}

// Shows the share sheet for `text` below the rectangle `x`, `y`, `width`, `height` (points,
// from the top left of the key window's content). False when no window can anchor it.
bool gitlama_share_text(const char *text, double x, double y, double width, double height) {
    NSWindow *window = [NSApp keyWindow] ?: [NSApp mainWindow];
    NSView *view = window.contentView;
    NSString *value = text ? [NSString stringWithUTF8String:text] : nil;
    if (view == nil || value == nil) {
        return false;
    }
    NSRect rect = NSMakeRect(x, y, MAX(width, 1), MAX(height, 1));
    if (!view.isFlipped) {
        rect.origin.y = NSHeight(view.bounds) - y - NSHeight(rect);
    }
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[ value ]];
    [picker showRelativeToRect:rect ofView:view preferredEdge:NSRectEdgeMinY];
    return true;
}
