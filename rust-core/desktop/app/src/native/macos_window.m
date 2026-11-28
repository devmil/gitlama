// The macOS window chrome, the reduce-motion setting and the share sheet.
//
// The window keeps its native frame with a unified, transparent toolbar title bar: the QML
// toolbar draws under it, beside the traffic lights. The share sheet offers a text (such as
// a diagnostics export) to the services the person has; no file is written.

#import <AppKit/AppKit.h>
#include <stdbool.h>

// The transparent, full-size title bar the QML toolbar draws under.
static void gitlama_apply_title_bar(NSWindow *window) {
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
}

void gitlama_configure_windows(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (window.toolbar != nil || (window.styleMask & NSWindowStyleMaskTitled) == 0) {
            continue;
        }
        gitlama_apply_title_bar(window);
        // macOS 13 is the minimum: the separator style replaces the toolbar's baseline.
        window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"GitLamaWindowToolbar"];
        window.toolbarStyle = NSWindowToolbarStyleUnified;
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        // Leaving full screen restores the style mask without the full-size content view
        // and Qt then sizes the frame for a title bar: an empty band appeared above the
        // toolbar and the window lost its height on every round trip. Put back the title bar
        // and the frame the window had before, after Qt's own handling of the notification.
        __weak NSWindow *weakWindow = window;
        __block NSRect windowed = window.frame;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:NSWindowWillEnterFullScreenNotification
                            object:window
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *notification) {
                          NSWindow *strongWindow = weakWindow;
                          if (strongWindow != nil) {
                              windowed = strongWindow.frame;
                          }
                        }];
        [center addObserverForName:NSWindowDidExitFullScreenNotification
                            object:window
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *notification) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                            NSWindow *strongWindow = weakWindow;
                            if (strongWindow == nil) {
                                return;
                            }
                            gitlama_apply_title_bar(strongWindow);
                            [strongWindow setFrame:windowed display:YES];
                          });
                        }];
    }
}

// The standard Window menu: Minimize (⌘M), Zoom, Enter Full Screen (⌃⌘F) and AppKit's list of
// the open windows. Qt's default menu bar has only the application menu, so these keys had no
// menu item to answer them. The titles arrive localized; calling again replaces the menu.
void gitlama_install_window_menu(const char *title, const char *minimize, const char *zoom,
                                 const char *full_screen) {
    NSMenu *bar = [NSApp mainMenu];
    if (bar == nil || title == NULL || minimize == NULL || zoom == NULL || full_screen == NULL) {
        return;
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:title]];
    NSMenuItem *item = [menu addItemWithTitle:[NSString stringWithUTF8String:minimize]
                                       action:@selector(performMiniaturize:)
                                keyEquivalent:@"m"];
    item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItemWithTitle:[NSString stringWithUTF8String:zoom]
                    action:@selector(performZoom:)
             keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    item = [menu addItemWithTitle:[NSString stringWithUTF8String:full_screen]
                           action:@selector(toggleFullScreen:)
                    keyEquivalent:@"f"];
    item.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;

    NSInteger index = [bar indexOfItemWithSubmenu:[NSApp windowsMenu]];
    if (index >= 0) {
        [bar removeItemAtIndex:index];
    }
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:menu.title action:nil keyEquivalent:@""];
    holder.submenu = menu;
    [bar addItem:holder];
    [NSApp setWindowsMenu:menu];
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
