#import "SPMenuBarPlayerController.h"
#import "SPPlayerWindow.h"
#import "SPBrowserDataSource.h"
#import "SPFloatingWidgetController.h"
#import "SPAudioProcessor.h"

static NSString * const kSPShowMenuBarItemKey = @"SPShowMenuBarItem";

@interface SPMenuBarPlayerController ()
{
    NSStatusItem *_statusItem;
    NSMenu *_statusMenu;
    
    NSMenuItem *_titleMenuItem;
    NSMenuItem *_authorMenuItem;
    NSMenuItem *_subtuneMenuItem;
    NSMenuItem *_chipMenuItem;
    
    NSMenuItem *_playPauseMenuItem;
    NSMenuItem *_stopMenuItem;
    NSMenuItem *_prevSubtuneMenuItem;
    NSMenuItem *_nextSubtuneMenuItem;
    NSMenuItem *_prevTrackMenuItem;
    NSMenuItem *_nextTrackMenuItem;
    
    NSMenuItem *_loopMenuItem;
    NSMenuItem *_volumeParentMenuItem;
    NSMenuItem *_crossfeedParentMenuItem;
    NSMenuItem *_widenerParentMenuItem;
    NSMenuItem *_floatingWidgetMenuItem;
    
    // Cached state
    NSString *_currentTitle;
    NSString *_currentAuthor;
    NSString *_currentReleaseInfo;
    NSInteger _currentSubtune;
    NSInteger _currentSubtuneCount;
    NSInteger _currentLength;
    NSString *_currentChip;
    BOOL _isCurrentMod;
    BOOL _isPlaying;
    NSTimeInterval _lastPlayTime;
    NSTimeInterval _lastTotalTime;
}

@end

@implementation SPMenuBarPlayerController

+ (instancetype)sharedController
{
    static SPMenuBarPlayerController *sSharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sSharedInstance = [[SPMenuBarPlayerController alloc] init];
    });
    return sSharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:kSPShowMenuBarItemKey] != nil) {
            _enabled = [defaults boolForKey:kSPShowMenuBarItemKey];
        } else {
            _enabled = YES;
            [defaults setBool:YES forKey:kSPShowMenuBarItemKey];
        }
        
        _currentTitle = @"No Tune Loaded";
        _currentAuthor = @"";
        _currentChip = @"MOS 6581";
        _currentSubtune = 1;
        _currentSubtuneCount = 1;
        _currentLength = 0;
        _isPlaying = NO;
    }
    return self;
}

- (void)setupWithPlayerWindow:(SPPlayerWindow *)window
{
    _playerWindow = window;
    
    if (_enabled) {
        [self createStatusItem];
    }
    [self updateViewMenuCheck];
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled != enabled) {
        _enabled = enabled;
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kSPShowMenuBarItemKey];
        
        if (enabled) {
            [self createStatusItem];
            [self refreshDisplay];
        } else {
            [self removeStatusItem];
        }
        [self updateViewMenuCheck];
    }
}

- (IBAction)toggleMenuBarItem:(id)sender
{
    self.enabled = !self.enabled;
}

- (void)createStatusItem
{
    if (_statusItem != nil) return;
    
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = _statusItem.button;
    if (button) {
        button.image = [self menuBarCassetteIcon];
        button.imagePosition = NSImageLeft;
        button.toolTip = @"SIDPLAY Mini-Player";
    }
    
    _statusMenu = [[NSMenu alloc] initWithTitle:@"SIDPLAY Menu Bar"];
    _statusMenu.autoenablesItems = NO;
    [self buildMenu];
    _statusItem.menu = _statusMenu;
}

- (void)removeStatusItem
{
    if (_statusItem != nil) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        _statusItem = nil;
        _statusMenu = nil;
    }
}

- (NSImage *)menuBarCassetteIcon
{
    NSImage *icon = [NSImage imageWithSize:NSMakeSize(18.0f, 18.0f) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        // Cassette outer body: 16.0 x 11.0, positioned at x=1.0, y=3.5
        NSRect shellRect = NSMakeRect(1.0f, 3.5f, 16.0f, 11.0f);
        NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:shellRect xRadius:1.5f yRadius:1.5f];
        [shell setLineWidth:1.2f];
        [[NSColor blackColor] setStroke];
        [shell stroke];
        
        // Center label/window cutout: 11.0 x 5.0, at x=3.5, y=6.0
        NSRect winRect = NSMakeRect(3.5f, 6.0f, 11.0f, 5.0f);
        NSBezierPath *win = [NSBezierPath bezierPathWithRoundedRect:winRect xRadius:1.0f yRadius:1.0f];
        [win setLineWidth:0.9f];
        [win stroke];
        
        // Left tape reel spool
        NSRect leftSpool = NSMakeRect(5.0f, 7.5f, 2.2f, 2.2f);
        [[NSBezierPath bezierPathWithOvalInRect:leftSpool] fill];
        
        // Right tape reel spool
        NSRect rightSpool = NSMakeRect(10.8f, 7.5f, 2.2f, 2.2f);
        [[NSBezierPath bezierPathWithOvalInRect:rightSpool] fill];
        
        // Tape tape ribbon bridge between reels
        NSRect bridge = NSMakeRect(7.0f, 8.2f, 4.0f, 0.8f);
        NSRectFill(bridge);
        
        // Bottom playback head notch
        NSBezierPath *notch = [NSBezierPath bezierPath];
        [notch moveToPoint:NSMakePoint(4.2f, 3.5f)];
        [notch lineToPoint:NSMakePoint(5.8f, 5.2f)];
        [notch lineToPoint:NSMakePoint(12.2f, 5.2f)];
        [notch lineToPoint:NSMakePoint(13.8f, 3.5f)];
        [notch setLineWidth:0.8f];
        [notch stroke];
        
        return YES;
    }];
    [icon setTemplate:YES];
    return icon;
}

- (void)buildMenu
{
    [_statusMenu removeAllItems];
    
    // 1. Song Title (Bold, primary)
    _titleMenuItem = [[NSMenuItem alloc] initWithTitle:@"No Tune Loaded" action:nil keyEquivalent:@""];
    _titleMenuItem.enabled = NO;
    [_statusMenu addItem:_titleMenuItem];
    
    // 2. Author & Release (Secondary)
    _authorMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    _authorMenuItem.enabled = NO;
    [_statusMenu addItem:_authorMenuItem];
    
    // 3. Subtune & Time Progress
    _subtuneMenuItem = [[NSMenuItem alloc] initWithTitle:@"Subtune 1 of 1  •  00:00 / 00:00" action:nil keyEquivalent:@""];
    _subtuneMenuItem.enabled = NO;
    [_statusMenu addItem:_subtuneMenuItem];
    
    // 4. Chip Model Badge
    _chipMenuItem = [[NSMenuItem alloc] initWithTitle:@"Hardware: MOS 6581 (SID)" action:nil keyEquivalent:@""];
    _chipMenuItem.enabled = NO;
    [_statusMenu addItem:_chipMenuItem];
    
    [_statusMenu addItem:[NSMenuItem separatorItem]];
    
    // 5. Play / Pause
    _playPauseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Play" action:@selector(menuClickPlayPause:) keyEquivalent:@""];
    _playPauseMenuItem.target = self;
    [_statusMenu addItem:_playPauseMenuItem];
    
    // 6. Stop
    _stopMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stop" action:@selector(menuClickStop:) keyEquivalent:@"."];
    _stopMenuItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _stopMenuItem.target = self;
    [_statusMenu addItem:_stopMenuItem];
    
    [_statusMenu addItem:[NSMenuItem separatorItem]];
    
    // 7. Previous / Next Subtune
    _prevSubtuneMenuItem = [[NSMenuItem alloc] initWithTitle:@"Previous Subtune" action:@selector(menuPreviousSubtune:) keyEquivalent:@"["];
    _prevSubtuneMenuItem.target = self;
    [_statusMenu addItem:_prevSubtuneMenuItem];
    
    _nextSubtuneMenuItem = [[NSMenuItem alloc] initWithTitle:@"Next Subtune" action:@selector(menuNextSubtune:) keyEquivalent:@"]"];
    _nextSubtuneMenuItem.target = self;
    [_statusMenu addItem:_nextSubtuneMenuItem];
    
    // 8. Previous / Next Track in Playlist
    _prevTrackMenuItem = [[NSMenuItem alloc] initWithTitle:@"Previous Track in Playlist" action:@selector(menuPreviousTrack:) keyEquivalent:@""];
    _prevTrackMenuItem.target = self;
    [_statusMenu addItem:_prevTrackMenuItem];
    
    _nextTrackMenuItem = [[NSMenuItem alloc] initWithTitle:@"Next Track in Playlist" action:@selector(menuNextTrack:) keyEquivalent:@""];
    _nextTrackMenuItem.target = self;
    [_statusMenu addItem:_nextTrackMenuItem];
    
    [_statusMenu addItem:[NSMenuItem separatorItem]];
    
    // 9. Looping Controls
    _loopMenuItem = [[NSMenuItem alloc] initWithTitle:@"Loop: Off ➡️" action:@selector(menuToggleLoop:) keyEquivalent:@""];
    _loopMenuItem.target = self;
    [_statusMenu addItem:_loopMenuItem];
    
    // 10. Volume Submenu
    _volumeParentMenuItem = [[NSMenuItem alloc] initWithTitle:@"Volume" action:nil keyEquivalent:@""];
    NSMenu *volMenu = [[NSMenu alloc] initWithTitle:@"Volume"];
    
    NSArray *volLevels = @[
        @{@"title": @"100% Maximum", @"val": @(1.0f)},
        @{@"title": @"75%", @"val": @(0.75f)},
        @{@"title": @"50%", @"val": @(0.50f)},
        @{@"title": @"25%", @"val": @(0.25f)},
        @{@"title": @"Mute (0%)", @"val": @(0.0f)}
    ];
    for (NSDictionary *dict in volLevels) {
        NSMenuItem *vItem = [[NSMenuItem alloc] initWithTitle:dict[@"title"] action:@selector(menuSelectVolume:) keyEquivalent:@""];
        vItem.target = self;
        vItem.representedObject = dict[@"val"];
        [volMenu addItem:vItem];
    }
    _volumeParentMenuItem.submenu = volMenu;
    [_statusMenu addItem:_volumeParentMenuItem];
    
    // 10b. Headphone Crossfeed
    _crossfeedParentMenuItem = [[NSMenuItem alloc] initWithTitle:@"Headphone Crossfeed" action:nil keyEquivalent:@""];
    NSMenu *cfMenu = [[NSMenu alloc] initWithTitle:@"Headphone Crossfeed"];
    NSArray *cfNames = @[
        @"Natural Crossfeed (Headphones)",
        @"Subtle Crossfeed",
        @"Off (Authentic Hard Stereo)",
        @"Mono Downmix"
    ];
    for (NSInteger i = 0; i < 4; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:cfNames[i]
                                                      action:@selector(menuSelectCrossfeed:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = i;
        [cfMenu addItem:item];
    }
    _crossfeedParentMenuItem.submenu = cfMenu;
    [_statusMenu addItem:_crossfeedParentMenuItem];
    
    // 10c. SID Spatial Widener
    _widenerParentMenuItem = [[NSMenuItem alloc] initWithTitle:@"SID Spatial Widener" action:nil keyEquivalent:@""];
    NSMenu *wMenu = [[NSMenu alloc] initWithTitle:@"SID Spatial Widener"];
    NSArray *wNames = @[
        @"Off (Authentic Mono)",
        @"Subtle Room Ambiance",
        @"Expansive Soundstage"
    ];
    for (NSInteger i = 0; i < 3; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:wNames[i]
                                                      action:@selector(menuSelectWidener:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = i;
        [wMenu addItem:item];
    }
    _widenerParentMenuItem.submenu = wMenu;
    [_statusMenu addItem:_widenerParentMenuItem];
    
    [_statusMenu addItem:[NSMenuItem separatorItem]];
    
    // 11. Open Main Window
    NSMenuItem *openAppItem = [[NSMenuItem alloc] initWithTitle:@"Open SIDPLAY" action:@selector(menuShowMainWindow:) keyEquivalent:@"o"];
    openAppItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    openAppItem.target = self;
    [_statusMenu addItem:openAppItem];
    
    // 12. Floating Retro Visualizer Widget
    _floatingWidgetMenuItem = [[NSMenuItem alloc] initWithTitle:@"Pop Out Floating Retro Visualizer" action:@selector(menuToggleFloatingWidget:) keyEquivalent:@"d"];
    _floatingWidgetMenuItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    _floatingWidgetMenuItem.target = self;
    [_statusMenu addItem:_floatingWidgetMenuItem];
    
    // 13. Preferences
    NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…" action:@selector(menuShowPreferences:) keyEquivalent:@","];
    prefsItem.target = self;
    [_statusMenu addItem:prefsItem];
    
    [_statusMenu addItem:[NSMenuItem separatorItem]];
    
    // 14. Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit SIDPLAY" action:@selector(menuQuitApp:) keyEquivalent:@"q"];
    quitItem.target = self;
    [_statusMenu addItem:quitItem];
    
    [self refreshDisplay];
}

- (void)refreshDisplay
{
    if (!_statusItem) return;
    
    // 1. Title item
    NSString *displayTitle = (_currentTitle && _currentTitle.length > 0) ? _currentTitle : @"No Tune Loaded";
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:13.0f],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    _titleMenuItem.attributedTitle = [[NSAttributedString alloc] initWithString:displayTitle attributes:titleAttrs];
    
    // 2. Author item
    NSMutableString *authorStr = [NSMutableString string];
    if (_currentAuthor && _currentAuthor.length > 0) {
        [authorStr appendString:_currentAuthor];
    }
    if (_currentReleaseInfo && _currentReleaseInfo.length > 0) {
        if (authorStr.length > 0) [authorStr appendString:@"  •  "];
        [authorStr appendString:_currentReleaseInfo];
    }
    if (authorStr.length == 0) {
        _authorMenuItem.hidden = YES;
    } else {
        _authorMenuItem.hidden = NO;
        NSDictionary *authorAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11.0f],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        };
        _authorMenuItem.attributedTitle = [[NSAttributedString alloc] initWithString:authorStr attributes:authorAttrs];
    }
    
    // 3. Subtune & Time
    [self updatePlaybackTime:_lastPlayTime totalTime:_lastTotalTime isPlaying:_isPlaying];
    
    // 4. Chip Badge
    NSString *chipStr = [NSString stringWithFormat:@"Hardware: %@ (%@)",
                         _currentChip ?: @"MOS 6581",
                         _isCurrentMod ? @"Commodore Amiga" : @"Commodore 64"];
    NSDictionary *chipAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.5f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };
    _chipMenuItem.attributedTitle = [[NSAttributedString alloc] initWithString:chipStr attributes:chipAttrs];
    
    // 5. Play / Pause
    _playPauseMenuItem.title = _isPlaying ? @"Pause" : @"Play";
    
    // 6. Tooltip
    if (_isPlaying && _currentTitle && _currentTitle.length > 0) {
        _statusItem.button.toolTip = [NSString stringWithFormat:@"SIDPLAY: %@ — %@", _currentTitle, _currentAuthor ?: @""];
    } else {
        _statusItem.button.toolTip = @"SIDPLAY Mini-Player";
    }
    
    // 7. Floating Widget State
    if (_floatingWidgetMenuItem) {
        BOOL isDetached = [SPFloatingWidgetController sharedController].isDetached;
        _floatingWidgetMenuItem.title = isDetached ? @"Dock Retro Visualizer" : @"Pop Out Floating Retro Visualizer";
    }
    
    // 8. Crossfeed & Widener checkmarks
    if (_crossfeedParentMenuItem && _crossfeedParentMenuItem.submenu) {
        SPCrossfeedMode cf = [SPAudioProcessor sharedProcessor].crossfeedMode;
        for (NSMenuItem *item in _crossfeedParentMenuItem.submenu.itemArray) {
            item.state = (item.tag == (NSInteger)cf) ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    if (_widenerParentMenuItem && _widenerParentMenuItem.submenu) {
        SPSpatialWidenerMode w = [SPAudioProcessor sharedProcessor].spatialWidenerMode;
        for (NSMenuItem *item in _widenerParentMenuItem.submenu.itemArray) {
            item.state = (item.tag == (NSInteger)w) ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    
    [self updateLoopMode];
    [self updateVolume];
}

- (void)menuSelectCrossfeed:(NSMenuItem *)sender
{
    [SPAudioProcessor sharedProcessor].crossfeedMode = (SPCrossfeedMode)sender.tag;
    [self refreshDisplay];
}

- (void)menuSelectWidener:(NSMenuItem *)sender
{
    [SPAudioProcessor sharedProcessor].spatialWidenerMode = (SPSpatialWidenerMode)sender.tag;
    [self refreshDisplay];
}

- (void)updatePlaybackState:(BOOL)isPlaying
{
    _isPlaying = isPlaying;
    _playPauseMenuItem.title = isPlaying ? @"Pause" : @"Play";
    if (_statusItem && _statusItem.button) {
        if (isPlaying && _currentTitle && _currentTitle.length > 0) {
            _statusItem.button.toolTip = [NSString stringWithFormat:@"SIDPLAY: %@ — %@", _currentTitle, _currentAuthor ?: @""];
        } else {
            _statusItem.button.toolTip = @"SIDPLAY Mini-Player";
        }
    }
}

- (void)updatePlaybackTime:(NSTimeInterval)currentTime totalTime:(NSTimeInterval)totalTime isPlaying:(BOOL)isPlaying
{
    _lastPlayTime = currentTime;
    _lastTotalTime = totalTime;
    _isPlaying = isPlaying;
    
    int curSec = (int)MAX(0, (NSInteger)currentTime);
    int totSec = (int)MAX(0, (NSInteger)totalTime);
    int remSec = (int)MAX(0, totSec - curSec);
    
    NSString *timeStr;
    if (totSec > 0) {
        timeStr = [NSString stringWithFormat:@"Song %02ld of %02ld  •  %02d:%02d / %02d:%02d (-%02d:%02d)",
                   (long)_currentSubtune, (long)_currentSubtuneCount,
                   curSec / 60, curSec % 60,
                   totSec / 60, totSec % 60,
                   remSec / 60, remSec % 60];
    } else {
        timeStr = [NSString stringWithFormat:@"Song %02ld of %02ld  •  %02d:%02d",
                   (long)_currentSubtune, (long)_currentSubtuneCount,
                   curSec / 60, curSec % 60];
    }
    
    NSDictionary *timeAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    _subtuneMenuItem.attributedTitle = [[NSAttributedString alloc] initWithString:timeStr attributes:timeAttrs];
}

- (void)updateTuneTitle:(NSString *)title
                 author:(NSString *)author
            releaseInfo:(NSString *)releaseInfo
                subtune:(NSInteger)subtune
           subtuneCount:(NSInteger)subtuneCount
                 length:(NSInteger)length
                   chip:(NSString *)chip
                  isMod:(BOOL)isMod
{
    _currentTitle = [title copy];
    _currentAuthor = [author copy];
    _currentReleaseInfo = [releaseInfo copy];
    _currentSubtune = subtune;
    _currentSubtuneCount = subtuneCount;
    _currentLength = length;
    _currentChip = [chip copy];
    _isCurrentMod = isMod;
    
    [self refreshDisplay];
}

- (void)updateLoopMode
{
    if (!_loopMenuItem) return;
    
    BOOL isSingle = NO;
    BOOL isAll = NO;
    if (_playerWindow) {
        isSingle = [_playerWindow isRepeatSingleActive];
        isAll = [_playerWindow isRepeatAllActive];
    }
    
    if (isSingle) {
        _loopMenuItem.title = @"Loop: Single Subtune 🔁1";
    } else if (isAll) {
        _loopMenuItem.title = @"Loop: All Tracks 🔁";
    } else {
        _loopMenuItem.title = @"Loop: Off ➡️";
    }
}

- (void)updateVolume
{
    if (!_volumeParentMenuItem || !_volumeParentMenuItem.submenu) return;
    
    float currentVol = 1.0f;
    if (_playerWindow && [_playerWindow respondsToSelector:@selector(playbackVolume)]) {
        currentVol = [_playerWindow playbackVolume];
    }
    
    for (NSMenuItem *item in _volumeParentMenuItem.submenu.itemArray) {
        if (item.representedObject) {
            float targetVal = [item.representedObject floatValue];
            BOOL isMatch = NO;
            if (targetVal == 0.0f && currentVol == 0.0f) {
                isMatch = YES;
            } else if (targetVal > 0.0f && fabs(currentVol - targetVal) < 0.13f) {
                isMatch = YES;
            }
            item.state = isMatch ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

- (void)updateViewMenuCheck
{
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenuItem *viewMenuItem = [mainMenu itemWithTitle:@"View"];
    if (viewMenuItem && viewMenuItem.submenu) {
        NSMenuItem *miniPlayerItem = [viewMenuItem.submenu itemWithTag:7771];
        if (miniPlayerItem) {
            miniPlayerItem.state = _enabled ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

#pragma mark - Menu Actions

- (void)menuClickPlayPause:(id)sender
{
    if (_playerWindow) {
        [_playerWindow clickPlayPauseButton:sender];
    }
}

- (void)menuClickStop:(id)sender
{
    if (_playerWindow) {
        [_playerWindow clickStopButton:sender];
    }
}

- (void)menuPreviousSubtune:(id)sender
{
    if (_playerWindow) {
        [_playerWindow previousSubtune:sender];
    }
}

- (void)menuNextSubtune:(id)sender
{
    if (_playerWindow) {
        [_playerWindow nextSubtune:sender];
    }
}

- (void)menuPreviousTrack:(id)sender
{
    if (_playerWindow && _playerWindow.browserDataSource) {
        [_playerWindow.browserDataSource playPreviousPlaylistItem:sender];
    }
}

- (void)menuNextTrack:(id)sender
{
    if (_playerWindow && _playerWindow.browserDataSource) {
        [_playerWindow.browserDataSource playNextPlaylistItem:sender];
    }
}

- (void)menuToggleLoop:(id)sender
{
    if (_playerWindow) {
        [_playerWindow toggleLoopMode];
        [self updateLoopMode];
    }
}

- (void)menuSelectVolume:(id)sender
{
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)sender;
        if (item.representedObject && _playerWindow) {
            float v = [item.representedObject floatValue];
            if ([_playerWindow respondsToSelector:@selector(setPlaybackVolume:)]) {
                [_playerWindow setPlaybackVolume:v];
            }
            [self updateVolume];
        }
    }
}

- (void)menuShowMainWindow:(id)sender
{
    if (_playerWindow) {
        [_playerWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)menuShowPreferences:(id)sender
{
    if (_playerWindow) {
        [_playerWindow showPreferencesWindow:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)menuToggleFloatingWidget:(id)sender
{
    if (_playerWindow) {
        [_playerWindow toggleFloatingVisualizerWidget:sender];
        [self refreshDisplay];
    }
}

- (void)menuQuitApp:(id)sender
{
    [NSApp terminate:nil];
}

@end
