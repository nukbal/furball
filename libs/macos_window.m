#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stddef.h>
#include <string.h>

// -----------------------------------------------------------------------------
// Window configuration
// -----------------------------------------------------------------------------

static const CGFloat MacOsHeaderHeight = 48.0;
static const CGFloat MacOsTrafficLightX = 16.0;

static char MacOsWindowControllerKey;
typedef void (*MacOsWindowRedrawCallback)(void *);


// -----------------------------------------------------------------------------
// Traffic lights
// -----------------------------------------------------------------------------

static NSView *MacOsGetTitleBarContainer(NSWindow *window) {
    NSButton *close = [window standardWindowButton:NSWindowCloseButton];

    if (close == nil || close.superview == nil || close.superview.superview == nil) {
        return nil;
    }

    return close.superview.superview;
}

static BOOL MacOsPointInsideButton(NSPoint pointInWindow, NSButton *button) {
    if (button == nil || button.hidden || button.superview == nil) {
        return NO;
    }
    NSPoint point = [button convertPoint:pointInWindow fromView:nil];

    return NSPointInRect(point, button.bounds);
}

static void MacOsLayoutTrafficLights(NSWindow *window) {
    if (window == nil) {
        return;
    }

    if ((window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        return;
    }

    NSButton *close = [window standardWindowButton:NSWindowCloseButton];
    NSButton *mini = [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoom = [window standardWindowButton:NSWindowZoomButton];

    if (close == nil || mini == nil || zoom == nil) {
        return;
    }

    NSView *container = MacOsGetTitleBarContainer(window);

    if (container == nil) {
        return;
    }

    const CGFloat buttonWidth = NSWidth(close.frame);
    const CGFloat buttonHeight = NSHeight(close.frame);
    const CGFloat padding = NSMinX(mini.frame) - NSMaxX(close.frame);

    NSRect frame = container.frame;
    frame.size.height = MacOsHeaderHeight;
    frame.origin.y = NSHeight(window.frame) - MacOsHeaderHeight;

    [container setFrame:frame];

    const CGFloat y = (MacOsHeaderHeight - buttonHeight) * 0.5;
    CGFloat x = MacOsTrafficLightX;

    [close setFrameOrigin:NSMakePoint(x, y)];

    x += buttonWidth + padding;
    [mini setFrameOrigin:NSMakePoint(x, y)];

    x += buttonWidth + padding;
    [zoom setFrameOrigin:NSMakePoint(x, y)];
}


// -----------------------------------------------------------------------------
// Window observer
//
// AppKit may recreate/re-layout parts of the native titlebar when the window
// changes state. We don't replace SDL's NSWindowDelegate; instead we observe
// the NSWindow and reapply our tiny amount of layout.
// -----------------------------------------------------------------------------

@interface MacOsWindowController : NSObject

@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) NSMutableArray *notificationTokens;
@property(nonatomic, strong) id eventMonitor;
@property(nonatomic, assign) MacOsWindowRedrawCallback redrawCallback;
@property(nonatomic, assign) void *redrawContext;

- (instancetype)initWithWindow:(NSWindow *)window redrawCallback:(MacOsWindowRedrawCallback)redrawCallback context:(void *)context;
- (void)scheduleLayout;

@end


@implementation MacOsWindowController

- (instancetype)initWithWindow:(NSWindow *)window redrawCallback:(MacOsWindowRedrawCallback)redrawCallback context:(void *)context {
    self = [super init];

    if (self == nil) {
        return nil;
    }

    _window = window;
    _notificationTokens = [NSMutableArray array];
    _redrawCallback = redrawCallback;
    _redrawContext = context;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    __weak MacOsWindowController *weakSelf = self;

    NSArray *notifications = @[
        NSWindowDidBecomeKeyNotification,
        NSWindowDidResizeNotification,
        NSWindowDidEndLiveResizeNotification,
        NSWindowDidExitFullScreenNotification,
        NSWindowDidChangeScreenNotification,
    ];

    for (NSNotificationName name in notifications) {
        id token = [center addObserverForName:name object:window queue:nil usingBlock:^(NSNotification *notification) {
            MacOsWindowController *controller = weakSelf;

            if (controller != nil) {
                [controller scheduleLayout];
                if (([notification.name isEqualToString:NSWindowDidResizeNotification] ||
                     [notification.name isEqualToString:NSWindowDidEndLiveResizeNotification]) && controller.redrawCallback != NULL) {
                    controller.redrawCallback(controller.redrawContext);
                }
            }
        }];

        [_notificationTokens addObject:token];
    }

    /*
     * Block AppKit's native titlebar double-click action.
     *
     * Instead of trying to infer the titlebar through contentLayoutRect,
     * we use the actual titlebar container that we resized to 40pt.
     *
     * Traffic light buttons themselves remain untouched.
     */
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp;

    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        MacOsWindowController *controller = weakSelf;
        NSWindow *targetWindow = controller.window;

        if (targetWindow == nil || event.window != targetWindow || event.clickCount < 2) {
            return event;
        }

        if ((targetWindow.styleMask & NSWindowStyleMaskFullScreen) != 0) {
            return event;
        }

        NSPoint location = event.locationInWindow;

        NSButton *closeButton = [targetWindow standardWindowButton:NSWindowCloseButton];
        NSButton *miniButton = [targetWindow standardWindowButton:NSWindowMiniaturizeButton];
        NSButton *zoomButton = [targetWindow standardWindowButton:NSWindowZoomButton];

        /*
         * Never interfere with the native traffic light controls.
         */
        if (MacOsPointInsideButton(location, closeButton) ||
            MacOsPointInsideButton(location, miniButton) ||
            MacOsPointInsideButton(location, zoomButton)) {
            return event;
        }

        NSView *container = MacOsGetTitleBarContainer(targetWindow);

        if (container == nil) {
            return event;
        }

        NSPoint pointInContainer = [container convertPoint:location fromView:nil];

        if (NSPointInRect(pointInContainer, container.bounds)) {
            /*
             * Consume the second click of a double-click sequence.
             * This prevents native titlebar zoom/minimize behavior.
             */
            return nil;
        }

        return event;
    }];

    return self;
}

- (void)scheduleLayout {
    __weak MacOsWindowController *weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        MacOsWindowController *controller = weakSelf;

        if (controller == nil) {
            return;
        }

        MacOsLayoutTrafficLights(controller.window);
    });
}

- (void)dealloc {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    for (id token in _notificationTokens) {
        [center removeObserver:token];
    }

    if (_eventMonitor != nil) {
        [NSEvent removeMonitor:_eventMonitor];
    }
}

@end


// -----------------------------------------------------------------------------
// Public window API
// -----------------------------------------------------------------------------

void MacOsWindowConfigure(void *windowPointer, MacOsWindowRedrawCallback redrawCallback, void *redrawContext) {
    if (windowPointer == NULL) {
        return;
    }

    NSWindow *window = (__bridge NSWindow *)windowPointer;

    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.movable = YES;
    window.movableByWindowBackground = NO;

    if (@available(macOS 11.0, *)) {
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    }

    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    NSButton *miniButton = [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];

    closeButton.hidden = NO;
    miniButton.hidden = NO;
    zoomButton.hidden = NO;

    /*
     * Install our observer once.
     */
    MacOsWindowController *controller = objc_getAssociatedObject(window, &MacOsWindowControllerKey);

    if (controller == nil) {
        controller = [[MacOsWindowController alloc] initWithWindow:window redrawCallback:redrawCallback context:redrawContext];

        objc_setAssociatedObject(
            window,
            &MacOsWindowControllerKey,
            controller,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    } else {
        controller.redrawCallback = redrawCallback;
        controller.redrawContext = redrawContext;
    }

    /*
     * Do one immediate layout and one next-runloop layout.
     *
     * The latter is important because AppKit may perform its own
     * titlebar layout after these properties have changed.
     */
    MacOsLayoutTrafficLights(window);
    [controller scheduleLayout];
}


/*
 * Optional manual update.
 */
void MacOsWindowUpdateLayout(void *windowPointer) {
    if (windowPointer == NULL) {
        return;
    }

    NSWindow *window = (__bridge NSWindow *)windowPointer;

    MacOsLayoutTrafficLights(window);
}


// -----------------------------------------------------------------------------
// Unicode NFC
// -----------------------------------------------------------------------------

BOOL MacOSIsTextNfc(const char *source, size_t length) {
    @autoreleasepool {
        NSString *string = [[NSString alloc] initWithBytes:source length:length encoding:NSUTF8StringEncoding];

        if (string == nil) {
            return NO;
        }

        return [string isEqualToString: [string precomposedStringWithCanonicalMapping]];
    }
}


size_t MacOSNormalizeText(const char *source, size_t length, char *destination, size_t capacity) {
    @autoreleasepool {
        NSString *string = [[NSString alloc] initWithBytes:source length:length encoding:NSUTF8StringEncoding];

        if (string == nil) {
            return SIZE_MAX;
        }

        NSData *utf8 = [[string precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];

        if (utf8 == nil) {
            return SIZE_MAX;
        }

        if (destination == NULL || capacity < utf8.length) {
            return utf8.length;
        }

        memcpy(destination, utf8.bytes, utf8.length);

        return utf8.length;
    }
}
