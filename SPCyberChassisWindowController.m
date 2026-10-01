//
//  SPCyberChassisWindowController.m
//  SIDPLAY
//
//  Window Controller for the Cyber-Chassis Deck
//

#import "SPCyberChassisWindowController.h"
#import "SPCyberChassisDeckView.h"
#import "SPPlayerWindow.h"
#import "SPThemeManager.h"

static NSString * const kSPCyberChassisDeckFrameKey = @"SPCyberChassisDeckWindowFrame";

@interface SPCyberChassisWindowController ()
{
    NSTimer *_refreshTimer;
}
@end

@implementation SPCyberChassisWindowController

+ (instancetype)sharedController
{
    static SPCyberChassisWindowController *sSharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[SPCyberChassisWindowController alloc] init];
    });
    return sSharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createDeckWindowIfNeeded];
        
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(playerStateChanged:) name:@"AudioPlayerStartedNotification" object:nil];
        [nc addObserver:self selector:@selector(playerStateChanged:) name:@"AudioPlayerStoppedNotification" object:nil];
        [nc addObserver:self selector:@selector(playerStateChanged:) name:@"AudioPlayerPauseNotification" object:nil];
        [nc addObserver:self selector:@selector(playerStateChanged:) name:@"AudioPlayerSubtuneChangedNotification" object:nil];
        [nc addObserver:self selector:@selector(themeChanged:) name:@"SPThemeDidChangeNotification" object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)createDeckWindowIfNeeded
{
    if (self.window != nil) return;
    
    NSRect screenRect = [NSScreen mainScreen].visibleFrame;
    NSRect defaultFrame = NSMakeRect(screenRect.origin.x + (screenRect.size.width - 550.0f) * 0.5f,
                                     screenRect.origin.y + (screenRect.size.height - 370.0f) * 0.5f,
                                     550.0f, 370.0f);
    
    NSString *savedFrame = [[NSUserDefaults standardUserDefaults] stringForKey:kSPCyberChassisDeckFrameKey];
    if (savedFrame && savedFrame.length > 0) {
        NSRect r = NSRectFromString(savedFrame);
        if (r.size.width >= 400.0f && r.size.height >= 300.0f) {
            defaultFrame = r;
        }
    }
    
    NSWindowStyleMask mask = NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable;
    
    NSWindow *win = [[NSWindow alloc] initWithContentRect:defaultFrame
                                                styleMask:mask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"Commodore 64 // Cyber-Chassis Deck";
    win.titlebarAppearsTransparent = YES;
    win.backgroundColor = [NSColor colorWithCalibratedWhite:0.1f alpha:1.0f];
    win.delegate = self;
    win.releasedWhenClosed = NO;
    
    _deckView = [[SPCyberChassisDeckView alloc] initWithFrame:NSMakeRect(0, 0, defaultFrame.size.width, defaultFrame.size.height)];
    _deckView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    win.contentView = _deckView;
    
    self.window = win;
}

- (void)setupWithPlayerWindow:(SPPlayerWindow *)playerWindow
{
    _playerWindow = playerWindow;
    _deckView.playerWindow = playerWindow;
}

- (BOOL)isDeckWindowVisible
{
    return self.window.isVisible;
}

- (IBAction)showDeckWindow:(id)sender
{
    [self createDeckWindowIfNeeded];
    [self.window makeKeyAndOrderFront:sender];
    [self startRefreshTimer];
    [_deckView updatePlayerState];
}

- (IBAction)toggleDeckWindow:(id)sender
{
    if (self.window.isVisible) {
        [self.window orderOut:sender];
        [self stopRefreshTimer];
    } else {
        [self showDeckWindow:sender];
    }
}

- (void)startRefreshTimer
{
    if (_refreshTimer) return;
    __weak typeof(self) weakSelf = self;
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 15.0) repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf.deckView updatePlayerState];
    }];
}

- (void)stopRefreshTimer
{
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)playerStateChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.deckView updatePlayerState];
    });
}

- (void)themeChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.deckView setNeedsDisplay:YES];
    });
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    [self stopRefreshTimer];
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (self.window) {
        NSString *frameStr = NSStringFromRect(self.window.frame);
        [[NSUserDefaults standardUserDefaults] setObject:frameStr forKey:kSPCyberChassisDeckFrameKey];
    }
}

@end
