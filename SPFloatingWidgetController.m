#import "SPFloatingWidgetController.h"
#import "SPPlayerWindow.h"
#import "SPSpectrumView.h"
#import "SPThemeManager.h"

static NSString * const kSPFloatingWidgetFrameKey = @"SPFloatingRetroVisualizerWidgetFrame";
static NSString * const kSPFloatingWidgetAlwaysOnTopKey = @"SPFloatingRetroVisualizerAlwaysOnTop";

#pragma mark - SPFloatingWidgetWindow

@implementation SPFloatingWidgetWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

- (void)performClose:(id)sender
{
    [[SPFloatingWidgetController sharedController] dockVisualizer];
}

- (void)cancelOperation:(id)sender
{
    [[SPFloatingWidgetController sharedController] dockVisualizer];
}

- (void)keyDown:(NSEvent *)event
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars isEqualToString:@"d"] || [chars isEqualToString:@"D"]) {
        [[SPFloatingWidgetController sharedController] dockVisualizer];
        return;
    } else if ([chars isEqualToString:@" "]) {
        SPPlayerWindow *win = [[SPFloatingWidgetController sharedController] playerWindow];
        if (win) [win clickPlayPauseButton:self];
        return;
    } else if ([chars isEqualToString:@"["]) {
        SPPlayerWindow *win = [[SPFloatingWidgetController sharedController] playerWindow];
        if (win) [win previousSubtune:self];
        return;
    } else if ([chars isEqualToString:@"]"]) {
        SPPlayerWindow *win = [[SPFloatingWidgetController sharedController] playerWindow];
        if (win) [win nextSubtune:self];
        return;
    }
    
    SPSpectrumView *sv = [[SPFloatingWidgetController sharedController] spectrumView];
    if (sv) {
        [sv keyDown:event];
    } else {
        [super keyDown:event];
    }
}

@end

#pragma mark - SPVisualizerPlaceholderView

@implementation SPVisualizerPlaceholderView

- (void)resetCursorRects
{
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    SPThemeManager *tm = [SPThemeManager sharedManager];
    
    // 1. Recessed dark backdrop
    NSColor *bgColor = [NSColor colorWithCalibratedWhite:0.06f alpha:0.85f];
    [bgColor setFill];
    NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 4.0f, 4.0f) xRadius:8.0f yRadius:8.0f];
    [bgPath fill];
    
    // 2. Dashed accent perimeter border
    NSColor *accent = [tm accentColor] ?: [NSColor controlAccentColor];
    [[accent colorWithAlphaComponent:0.45f] setStroke];
    CGFloat dashPattern[] = { 6.0f, 4.0f };
    [bgPath setLineDash:dashPattern count:2 phase:0.0f];
    [bgPath setLineWidth:1.5f];
    [bgPath stroke];
    
    // 3. Floating window icon illustration
    CGFloat centerY = bounds.origin.y + bounds.size.height * 0.5f;
    CGFloat centerX = bounds.origin.x + bounds.size.width * 0.5f;
    
    NSRect iconRect = NSMakeRect(centerX - 24.0f, centerY + 10.0f, 48.0f, 32.0f);
    NSBezierPath *iconWin = [NSBezierPath bezierPathWithRoundedRect:iconRect xRadius:4.0f yRadius:4.0f];
    [[NSColor colorWithCalibratedWhite:0.2f alpha:0.8f] setFill];
    [iconWin fill];
    [[accent colorWithAlphaComponent:0.8f] setStroke];
    [iconWin setLineWidth:1.2f];
    [iconWin stroke];
    
    // Screen titlebar line
    NSRect titleLine = NSMakeRect(iconRect.origin.x, iconRect.origin.y + iconRect.size.height - 7.0f, iconRect.size.width, 7.0f);
    [[NSColor colorWithCalibratedWhite:0.3f alpha:0.9f] setFill];
    NSRectFill(titleLine);
    
    // Floating pop-out arrow symbol
    NSString *arrowStr = @"↗";
    NSDictionary *arrowAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: accent
    };
    NSSize arrSize = [arrowStr sizeWithAttributes:arrowAttr];
    [arrowStr drawAtPoint:NSMakePoint(iconRect.origin.x + (iconRect.size.width - arrSize.width)*0.5f,
                                      iconRect.origin.y + (iconRect.size.height - 7.0f - arrSize.height)*0.5f)
           withAttributes:arrowAttr];
    
    // 4. Informational text
    NSString *mainText = @"RETRO VISUALIZER DETACHED";
    NSDictionary *mainAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSSize mainSize = [mainText sizeWithAttributes:mainAttr];
    [mainText drawAtPoint:NSMakePoint(centerX - mainSize.width * 0.5f, centerY - 20.0f) withAttributes:mainAttr];
    
    NSString *subText = @"Floating on your desktop";
    NSDictionary *subAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.0f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    NSSize subSize = [subText sizeWithAttributes:subAttr];
    [subText drawAtPoint:NSMakePoint(centerX - subSize.width * 0.5f, centerY - 36.0f) withAttributes:subAttr];
    
    // 5. Dock button badge
    NSString *btnText = @"⤓  Click to Dock Back";
    NSDictionary *btnAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.5f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize btnSize = [btnText sizeWithAttributes:btnAttr];
    NSRect btnRect = NSMakeRect(centerX - (btnSize.width + 20.0f)*0.5f, centerY - 68.0f, btnSize.width + 20.0f, 22.0f);
    
    NSBezierPath *btnPill = [NSBezierPath bezierPathWithRoundedRect:btnRect xRadius:11.0f yRadius:11.0f];
    [[accent colorWithAlphaComponent:0.85f] setFill];
    [btnPill fill];
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.3f] setStroke];
    [btnPill setLineWidth:0.75f];
    [btnPill stroke];
    
    [btnText drawAtPoint:NSMakePoint(btnRect.origin.x + 10.0f, btnRect.origin.y + 3.0f) withAttributes:btnAttr];
}

- (void)mouseDown:(NSEvent *)event
{
    if (self.target && self.action && [self.target respondsToSelector:self.action]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
        #pragma clang diagnostic pop
    }
}

@end

#pragma mark - SPFloatingWidgetController

@interface SPFloatingWidgetController () <NSWindowDelegate>
{
    SPFloatingWidgetWindow *_floatingWindow;
    SPVisualizerPlaceholderView *_placeholderView;
    NSVisualEffectView *_visualEffectView;
    NSButton *_dockButton;
    NSTextField *_titleOverlayField;
    NSTrackingArea *_widgetTrackingArea;
    NSTimer *_overlayFadeTimer;
    
    NSView *_originalSuperview;
    NSRect _originalFrame;
    NSAutoresizingMaskOptions _originalAutoresizingMask;
    
    BOOL _isDetached;
    BOOL _alwaysOnTop;
}

@end

@implementation SPFloatingWidgetController

+ (instancetype)sharedController
{
    static SPFloatingWidgetController *sSharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[SPFloatingWidgetController alloc] init];
    });
    return sSharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _isDetached = NO;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:kSPFloatingWidgetAlwaysOnTopKey] != nil) {
            _alwaysOnTop = [defaults boolForKey:kSPFloatingWidgetAlwaysOnTopKey];
        } else {
            _alwaysOnTop = YES;
            [defaults setBool:YES forKey:kSPFloatingWidgetAlwaysOnTopKey];
        }
    }
    return self;
}

- (void)setupWithPlayerWindow:(SPPlayerWindow *)playerWindow spectrumView:(SPSpectrumView *)spectrumView
{
    _playerWindow = playerWindow;
    _spectrumView = spectrumView;
    [self updateViewMenuChecks];
}

- (void)createFloatingWindowIfNeeded
{
    if (_floatingWindow != nil) return;
    
    NSRect screenRect = [NSScreen mainScreen].visibleFrame;
    NSRect defaultFrame = NSMakeRect(screenRect.origin.x + screenRect.size.width - 460.0f,
                                     screenRect.origin.y + screenRect.size.height - 320.0f,
                                     420.0f, 270.0f);
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedFrameStr = [defaults stringForKey:kSPFloatingWidgetFrameKey];
    if (savedFrameStr && savedFrameStr.length > 0) {
        NSRect saved = NSRectFromString(savedFrameStr);
        if (saved.size.width >= 240.0f && saved.size.height >= 160.0f) {
            defaultFrame = saved;
        }
    }
    
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskResizable |
                                  NSWindowStyleMaskFullSizeContentView;
                                  
    _floatingWindow = [[SPFloatingWidgetWindow alloc] initWithContentRect:defaultFrame
                                                                styleMask:styleMask
                                                                  backing:NSBackingStoreBuffered
                                                                    defer:NO];
                                                                    
    _floatingWindow.titlebarAppearsTransparent = YES;
    _floatingWindow.titleVisibility = NSWindowTitleHidden;
    _floatingWindow.movableByWindowBackground = YES;
    _floatingWindow.backgroundColor = [NSColor clearColor];
    _floatingWindow.opaque = NO;
    _floatingWindow.hasShadow = YES;
    _floatingWindow.minSize = NSMakeSize(260.0f, 170.0f);
    _floatingWindow.contentAspectRatio = NSMakeSize(16.0f, 10.0f);
    _floatingWindow.level = _alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
    _floatingWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _floatingWindow.delegate = self;
    
    NSView *rootContent = _floatingWindow.contentView;
    rootContent.wantsLayer = YES;
    rootContent.layer.cornerRadius = 12.0f;
    rootContent.layer.masksToBounds = YES;
    
    // Acrylic frosted backdrop
    _visualEffectView = [[NSVisualEffectView alloc] initWithFrame:rootContent.bounds];
    _visualEffectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _visualEffectView.material = NSVisualEffectMaterialHUDWindow;
    _visualEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _visualEffectView.state = NSVisualEffectStateActive;
    _visualEffectView.wantsLayer = YES;
    _visualEffectView.layer.cornerRadius = 12.0f;
    _visualEffectView.layer.borderWidth = 1.0f;
    _visualEffectView.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.20f].CGColor;
    [rootContent addSubview:_visualEffectView];
    
    // Top-right docking button
    _dockButton = [[NSButton alloc] initWithFrame:NSMakeRect(rootContent.bounds.size.width - 32.0f, rootContent.bounds.size.height - 32.0f, 24.0f, 24.0f)];
    _dockButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    _dockButton.bezelStyle = NSBezelStyleRegularSquare;
    _dockButton.bordered = NO;
    _dockButton.wantsLayer = YES;
    _dockButton.layer.cornerRadius = 12.0f;
    _dockButton.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0f alpha:0.45f].CGColor;
    _dockButton.title = @"⤓";
    _dockButton.font = [NSFont systemFontOfSize:14.0f weight:NSFontWeightBold];
    _dockButton.contentTintColor = [NSColor whiteColor];
    _dockButton.toolTip = @"Dock Retro Visualizer back into Main Window (⌃⌥D)";
    _dockButton.target = self;
    _dockButton.action = @selector(dockVisualizer);
    [rootContent addSubview:_dockButton positioned:NSWindowAbove relativeTo:nil];
    
    // Bottom track info overlay pill
    _titleOverlayField = [[NSTextField alloc] initWithFrame:NSMakeRect(16.0f, 10.0f, rootContent.bounds.size.width - 32.0f, 22.0f)];
    _titleOverlayField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _titleOverlayField.editable = NO;
    _titleOverlayField.selectable = NO;
    _titleOverlayField.bordered = NO;
    _titleOverlayField.backgroundColor = [NSColor colorWithCalibratedWhite:0.08f alpha:0.82f];
    _titleOverlayField.wantsLayer = YES;
    _titleOverlayField.layer.cornerRadius = 11.0f;
    _titleOverlayField.layer.borderWidth = 0.5f;
    _titleOverlayField.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.25f].CGColor;
    _titleOverlayField.alignment = NSTextAlignmentCenter;
    _titleOverlayField.font = [NSFont monospacedDigitSystemFontOfSize:10.0f weight:NSFontWeightMedium];
    _titleOverlayField.textColor = [NSColor whiteColor];
    _titleOverlayField.alphaValue = 0.0f; // Hidden by default, fades in on hover/change
    [rootContent addSubview:_titleOverlayField positioned:NSWindowAbove relativeTo:nil];
    
    // Tracking area for overlay auto-reveal
    _widgetTrackingArea = [[NSTrackingArea alloc] initWithRect:rootContent.bounds
                                                       options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self
                                                      userInfo:nil];
    [rootContent addTrackingArea:_widgetTrackingArea];
}

- (void)detachVisualizer
{
    if (_isDetached || _spectrumView == nil) return;
    
    [self createFloatingWindowIfNeeded];
    
    _originalSuperview = _spectrumView.superview;
    _originalFrame = _spectrumView.frame;
    _originalAutoresizingMask = _spectrumView.autoresizingMask;
    
    // Insert placeholder in place of spectrumView in the main window
    _placeholderView = [[SPVisualizerPlaceholderView alloc] initWithFrame:_originalFrame];
    _placeholderView.autoresizingMask = _originalAutoresizingMask;
    _placeholderView.target = self;
    _placeholderView.action = @selector(dockVisualizer);
    
    [_originalSuperview addSubview:_placeholderView positioned:NSWindowAbove relativeTo:_spectrumView];
    [_spectrumView removeFromSuperview];
    
    // Insert spectrumView into floating window
    NSView *rootContent = _floatingWindow.contentView;
    _spectrumView.frame = rootContent.bounds;
    _spectrumView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // Place visualizer right on top of background visual effect view, beneath overlay controls
    [rootContent addSubview:_spectrumView positioned:NSWindowAbove relativeTo:_visualEffectView];
    [rootContent addSubview:_dockButton positioned:NSWindowAbove relativeTo:_spectrumView];
    [rootContent addSubview:_titleOverlayField positioned:NSWindowAbove relativeTo:_spectrumView];
    
    _isDetached = YES;
    [_floatingWindow makeKeyAndOrderFront:nil];
    [_spectrumView setNeedsDisplay:YES];
    [_spectrumView showNotification:@"Detached as Floating Widget (⌃⌥D)"];
    
    [self updateViewMenuChecks];
}

- (void)dockVisualizer
{
    if (!_isDetached || _spectrumView == nil || _originalSuperview == nil) return;
    
    // Save current window frame
    if (_floatingWindow) {
        NSString *frameStr = NSStringFromRect(_floatingWindow.frame);
        [[NSUserDefaults standardUserDefaults] setObject:frameStr forKey:kSPFloatingWidgetFrameKey];
        [_floatingWindow orderOut:nil];
    }
    
    [_spectrumView removeFromSuperview];
    if (_placeholderView) {
        [_placeholderView removeFromSuperview];
        _placeholderView = nil;
    }
    
    _spectrumView.frame = _originalFrame;
    _spectrumView.autoresizingMask = _originalAutoresizingMask;
    [_originalSuperview addSubview:_spectrumView];
    
    _isDetached = NO;
    [_spectrumView setNeedsDisplay:YES];
    [_spectrumView showNotification:@"Docked into Main Window"];
    
    if (_playerWindow) {
        [_playerWindow makeKeyAndOrderFront:nil];
    }
    [self updateViewMenuChecks];
}

- (void)toggleFloatingWidget
{
    if (_isDetached) {
        [self dockVisualizer];
    } else {
        [self detachVisualizer];
    }
}

- (void)setAlwaysOnTop:(BOOL)alwaysOnTop
{
    _alwaysOnTop = alwaysOnTop;
    [[NSUserDefaults standardUserDefaults] setBool:alwaysOnTop forKey:kSPFloatingWidgetAlwaysOnTopKey];
    if (_floatingWindow) {
        _floatingWindow.level = alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
    }
}

- (void)updateOverlayInfoWithTitle:(NSString *)title author:(NSString *)author chip:(NSString *)chip isMod:(BOOL)isMod
{
    if (!_titleOverlayField) return;
    
    NSString *t = (title && title.length > 0) ? title : @"No Tune";
    NSString *a = (author && author.length > 0) ? author : @"";
    NSString *c = chip ?: @"MOS 6581";
    
    NSString *info = [NSString stringWithFormat:@"%@%@%@  •  %@", t, (a.length > 0 ? @" — " : @""), a, c];
    _titleOverlayField.stringValue = info;
    
    // Temporarily flash overlay on track change
    if (_isDetached) {
        [self showOverlayTemporarily];
    }
}

- (void)showOverlayTemporarily
{
    if (!_titleOverlayField) return;
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        self->_titleOverlayField.animator.alphaValue = 1.0f;
    } completionHandler:^{
        [self->_overlayFadeTimer invalidate];
        self->_overlayFadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                                   target:self
                                                                 selector:@selector(fadeOverlayOut)
                                                                 userInfo:nil
                                                                  repeats:NO];
    }];
}

- (void)fadeOverlayOut
{
    if (!_titleOverlayField) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.5;
        self->_titleOverlayField.animator.alphaValue = 0.0f;
    }];
}

- (void)mouseEntered:(NSEvent *)event
{
    [self showOverlayTemporarily];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        self->_dockButton.animator.alphaValue = 1.0f;
    }];
}

- (void)mouseExited:(NSEvent *)event
{
    [self fadeOverlayOut];
}

- (void)updateViewMenuChecks
{
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenuItem *viewMenuItem = [mainMenu itemWithTitle:@"View"];
    if (viewMenuItem && viewMenuItem.submenu) {
        NSMenuItem *widgetItem = [viewMenuItem.submenu itemWithTag:7772];
        if (widgetItem) {
            widgetItem.title = _isDetached ? @"Dock Retro Visualizer" : @"Detach Floating Retro Visualizer";
            widgetItem.state = _isDetached ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    if (notification.object == _floatingWindow && _isDetached) {
        [self dockVisualizer];
    }
}

@end
