//
//  SPCyberChassisDeckView.m
//  SIDPLAY
//
//  Brushed Gunmetal Cyber-Chassis Deck View
//  Integrating Nixie Tube Display, Circular Phosphor Vector Scope,
//  Knurled Aluminum Rotary Knobs, and Chrome Bat Toggle Switches.
//

#import "SPCyberChassisDeckView.h"
#import "SPPlayerWindow.h"
#import "PlayerLibSidplayWrapper.h"
#import "SPThemeManager.h"
#import <QuartzCore/QuartzCore.h>

@interface SPCyberDeckButton : NSButton
@end

@implementation SPCyberDeckButton

- (instancetype)initWithFrame:(NSRect)frameRect title:(NSString *)title
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.title = title;
        self.bezelStyle = NSBezelStyleRegularSquare;
        [self setButtonType:NSButtonTypeMomentaryPushIn];
        [self setBordered:NO];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5f, 0.5f) xRadius:3.5f yRadius:3.5f];
    
    BOOL isPressed = [self.cell isHighlighted];
    NSColor *topColor = isPressed ? [NSColor colorWithCalibratedWhite:0.12f alpha:1.0f] : [NSColor colorWithCalibratedWhite:0.25f alpha:1.0f];
    NSColor *botColor = isPressed ? [NSColor colorWithCalibratedWhite:0.06f alpha:1.0f] : [NSColor colorWithCalibratedWhite:0.13f alpha:1.0f];
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:topColor endingColor:botColor];
    [grad drawInBezierPath:path angle:-90.0f];
    
    NSColor *strokeCol = isPressed ? [NSColor colorWithCalibratedRed:1.0f green:0.80f blue:0.30f alpha:0.95f]
                                   : [NSColor colorWithCalibratedRed:0.35f green:0.40f blue:0.48f alpha:0.85f];
    [strokeCol setStroke];
    path.lineWidth = 1.0f;
    [path stroke];
    
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSFont *font = [NSFont boldSystemFontOfSize:11.0f];
    NSColor *textCol = isPressed ? [NSColor colorWithCalibratedRed:1.0f green:0.85f blue:0.35f alpha:1.0f]
                                 : [NSColor colorWithCalibratedRed:0.88f green:0.92f blue:0.96f alpha:0.95f];
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textCol,
        NSParagraphStyleAttributeName: style
    };
    CGFloat textH = [font pointSize] + 2.0f;
    CGFloat textY = (bounds.size.height - textH) * 0.5f;
    [self.title drawInRect:NSMakeRect(0, textY, bounds.size.width, textH) withAttributes:attrs];
}

@end

@interface SPCyberChassisDeckView ()
{
    NSTextField *_statusTitleField;
    NSTextField *_statusSubtitleField;
}
@end

@implementation SPCyberChassisDeckView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    [self setWantsLayer:YES];
    
    // 1. Time Nixie Display (MM:SS)
    _timeNixieView = [[SPNixieDisplayView alloc] initWithFrame:NSMakeRect(18, 10, 142, 74)];
    _timeNixieView.showSubtune = NO;
    _timeNixieView.allowToggleOnMouseDown = NO;
    _timeNixieView.customLabel = @"TRACK TIME";
    _timeNixieView.subLabel = @"MINUTES : SECONDS";
    _timeNixieView.toolTip = @"Playback Elapsed Time (Minutes : Seconds)";
    [_timeNixieView setTimeInSeconds:0];
    [self addSubview:_timeNixieView];
    
    // 2. Subtune Nixie Display (01/01)
    _subtuneNixieView = [[SPNixieDisplayView alloc] initWithFrame:NSMakeRect(168, 10, 142, 74)];
    _subtuneNixieView.showSubtune = YES;
    _subtuneNixieView.allowToggleOnMouseDown = NO;
    _subtuneNixieView.customLabel = @"SUBTUNE SONG";
    _subtuneNixieView.subLabel = @"CURRENT / TOTAL";
    _subtuneNixieView.toolTip = @"Subtune Song: Current / Total Songs in SID file (Click to step forward)";
    __weak typeof(self) weakSelf = self;
    _subtuneNixieView.clickHandler = ^(SPNixieDisplayView *v) {
        [weakSelf nextSubtuneClicked:v];
    };
    [_subtuneNixieView setSubtune:1 count:1];
    [self addSubview:_subtuneNixieView];
    
    // 2b. Subtune Stepper Buttons (◀ and ▶)
    _prevSubtuneBtn = [[SPCyberDeckButton alloc] initWithFrame:NSMakeRect(316, 10, 26, 32) title:@"◀"];
    _prevSubtuneBtn.toolTip = @"Previous Subtune Song";
    _prevSubtuneBtn.target = self;
    _prevSubtuneBtn.action = @selector(prevSubtuneClicked:);
    [self addSubview:_prevSubtuneBtn];
    
    _nextSubtuneBtn = [[SPCyberDeckButton alloc] initWithFrame:NSMakeRect(316, 46, 26, 32) title:@"▶"];
    _nextSubtuneBtn.toolTip = @"Next Subtune Song";
    _nextSubtuneBtn.target = self;
    _nextSubtuneBtn.action = @selector(nextSubtuneClicked:);
    [self addSubview:_nextSubtuneBtn];
    
    // 3. Circular Phosphor Vector Scope
    _vectorScopeView = [[SPCircularVectorScopeView alloc] initWithFrame:NSMakeRect(600, 10, 160, 160)];
    _vectorScopeView.scopeMode = SPVectorScopeModeLissajousXY;
    [self addSubview:_vectorScopeView];
    
    // 4. Knurled Rotary Knobs
    _volumeKnob = [[SPKnurledKnobControl alloc] initWithFrame:NSMakeRect(235, 10, 70, 120)
                                                        title:@"VOLUME"
                                                         unit:@"%"
                                                     minValue:0.0f
                                                     maxValue:100.0f
                                                 initialValue:80.0f
                                                        color:SPKnobColorCyan];
    _volumeKnob.target = self;
    _volumeKnob.action = @selector(volumeKnobChanged:);
    [self addSubview:_volumeKnob];
    
    _tempoKnob = [[SPKnurledKnobControl alloc] initWithFrame:NSMakeRect(310, 10, 70, 120)
                                                       title:@"TEMPO"
                                                        unit:@"%"
                                                    minValue:50.0f
                                                    maxValue:200.0f
                                                initialValue:100.0f
                                                       color:SPKnobColorAmber];
    _tempoKnob.target = self;
    _tempoKnob.action = @selector(tempoKnobChanged:);
    [self addSubview:_tempoKnob];
    
    _filterKnob = [[SPKnurledKnobControl alloc] initWithFrame:NSMakeRect(385, 10, 70, 120)
                                                        title:@"RESONANCE"
                                                         unit:@"%"
                                                     minValue:0.0f
                                                     maxValue:100.0f
                                                 initialValue:50.0f
                                                        color:SPKnobColorEmerald];
    _filterKnob.target = self;
    _filterKnob.action = @selector(filterKnobChanged:);
    [self addSubview:_filterKnob];
    
    // 5. Heavy Bat Toggle Switches
    _playPauseToggle = [[SPToggleSwitchControl alloc] initWithFrame:NSMakeRect(465, 10, 42, 115)
                                                             title:@"PLAY"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorEmerald];
    _playPauseToggle.target = self;
    _playPauseToggle.action = @selector(playPauseToggled:);
    [self addSubview:_playPauseToggle];
    
    _loopToggle = [[SPToggleSwitchControl alloc] initWithFrame:NSMakeRect(510, 10, 42, 115)
                                                         title:@"LOOP"
                                                          isOn:NO
                                                      ledColor:SPToggleLedColorAmber];
    _loopToggle.target = self;
    _loopToggle.action = @selector(loopToggled:);
    [self addSubview:_loopToggle];
    
    _stereoSidToggle = [[SPToggleSwitchControl alloc] initWithFrame:NSMakeRect(555, 10, 42, 115)
                                                             title:@"DUAL SID"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorCyan];
    _stereoSidToggle.target = self;
    _stereoSidToggle.action = @selector(stereoSidToggled:);
    [self addSubview:_stereoSidToggle];
    
    _scopeModeToggle = [[SPToggleSwitchControl alloc] initWithFrame:NSMakeRect(600, 10, 42, 115)
                                                             title:@"SCOPE"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorAmber];
    _scopeModeToggle.target = self;
    _scopeModeToggle.action = @selector(scopeModeToggled:);
    [self addSubview:_scopeModeToggle];
}

- (void)layout
{
    [super layout];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 100.0f || h < 60.0f) return;
    
    if (h <= 260.0f) {
        // Horizontal Rack-Mount Strip (embedded in player window or wide HUD)
        CGFloat bottomY = 12.0f;
        CGFloat ctrlH = h - 24.0f;
        
        // 1. Nixie Displays (Left bay - expanded horizontally for full 4-tube + separator display)
        CGFloat nixieH = MIN(78.0f, MAX(20.0f, ctrlH - 4.0f));
        CGFloat nixieY = bottomY + MAX(0.0f, (ctrlH - nixieH) * 0.5f);
        CGFloat nixieW = 142.0f;
        _timeNixieView.frame = NSMakeRect(18.0f, nixieY, nixieW, nixieH);
        _subtuneNixieView.frame = NSMakeRect(18.0f + nixieW + 8.0f, nixieY, nixieW, nixieH);
        
        // Subtune Stepper buttons (◀ and ▶)
        CGFloat btnX = 18.0f + (nixieW * 2.0f) + 12.0f;
        CGFloat btnW = 26.0f;
        CGFloat btnH = MAX(10.0f, (nixieH - 4.0f) * 0.5f);
        _nextSubtuneBtn.frame = NSMakeRect(btnX, nixieY + btnH + 4.0f, btnW, btnH);
        _prevSubtuneBtn.frame = NSMakeRect(btnX, nixieY, btnW, btnH);
        
        // 2. Knurled Knobs
        CGFloat knobAreaX = btnX + btnW + 16.0f;
        CGFloat knobW = 68.0f;
        CGFloat knobH = MIN(120.0f, ctrlH);
        CGFloat knobY = bottomY + (ctrlH - knobH) * 0.5f;
        _volumeKnob.frame = NSMakeRect(knobAreaX, knobY, knobW, knobH);
        _tempoKnob.frame = NSMakeRect(knobAreaX + knobW + 6.0f, knobY, knobW, knobH);
        _filterKnob.frame = NSMakeRect(knobAreaX + (knobW + 6.0f) * 2.0f, knobY, knobW, knobH);
        
        // 3. Bat Toggle Switches
        CGFloat toggleAreaX = knobAreaX + (knobW + 6.0f) * 3.0f + 14.0f;
        CGFloat toggleW = 42.0f;
        CGFloat toggleH = MIN(116.0f, ctrlH);
        CGFloat toggleY = bottomY + (ctrlH - toggleH) * 0.5f;
        _playPauseToggle.frame = NSMakeRect(toggleAreaX, toggleY, toggleW, toggleH);
        _loopToggle.frame = NSMakeRect(toggleAreaX + toggleW + 4.0f, toggleY, toggleW, toggleH);
        _stereoSidToggle.frame = NSMakeRect(toggleAreaX + (toggleW + 4.0f) * 2.0f, toggleY, toggleW, toggleH);
        _scopeModeToggle.frame = NSMakeRect(toggleAreaX + (toggleW + 4.0f) * 3.0f, toggleY, toggleW, toggleH);
        
        // 4. Vector Scope (Right bay)
        CGFloat scopeX = toggleAreaX + (toggleW + 4.0f) * 4.0f + 16.0f;
        CGFloat maxScopeW = w - scopeX - 20.0f;
        CGFloat scopeDim = MIN(maxScopeW, ctrlH);
        if (scopeDim >= 50.0f) {
            _vectorScopeView.frame = NSMakeRect(scopeX, bottomY + (ctrlH - scopeDim) * 0.5f, scopeDim, scopeDim);
            _vectorScopeView.hidden = NO;
        } else {
            _vectorScopeView.hidden = YES;
        }
    } else {
        // Standard / Compact Two-Row Layout (for dedicated window)
        CGFloat topRowY = h - 110.0f;
        CGFloat nixieW = 142.0f;
        CGFloat nixieH = 74.0f;
        _timeNixieView.frame = NSMakeRect(18.0f, topRowY, nixieW, nixieH);
        _subtuneNixieView.frame = NSMakeRect(18.0f + nixieW + 8.0f, topRowY, nixieW, nixieH);
        
        CGFloat btnX = 18.0f + (nixieW * 2.0f) + 12.0f;
        CGFloat btnW = 26.0f;
        CGFloat btnH = (nixieH - 4.0f) * 0.5f;
        _nextSubtuneBtn.frame = NSMakeRect(btnX, topRowY + btnH + 4.0f, btnW, btnH);
        _prevSubtuneBtn.frame = NSMakeRect(btnX, topRowY, btnW, btnH);
        
        CGFloat scopeSize = MIN(w - 370.0f - 24.0f, 150.0f);
        if (scopeSize > 50.0f) {
            _vectorScopeView.frame = NSMakeRect(w - scopeSize - 20.0f, h - scopeSize - 20.0f, scopeSize, scopeSize);
            _vectorScopeView.hidden = NO;
        } else {
            _vectorScopeView.hidden = YES;
        }
        
        CGFloat botH = MIN(126.0f, topRowY - 24.0f);
        _volumeKnob.frame = NSMakeRect(20.0f, 16.0f, 78.0f, botH);
        _tempoKnob.frame = NSMakeRect(104.0f, 16.0f, 78.0f, botH);
        _filterKnob.frame = NSMakeRect(188.0f, 16.0f, 78.0f, botH);
        
        CGFloat togX = 276.0f;
        _playPauseToggle.frame = NSMakeRect(togX, 18.0f, 44.0f, botH);
        _loopToggle.frame = NSMakeRect(togX + 48.0f, 18.0f, 44.0f, botH);
        _stereoSidToggle.frame = NSMakeRect(togX + 96.0f, 18.0f, 44.0f, botH);
        _scopeModeToggle.frame = NSMakeRect(togX + 144.0f, 18.0f, 44.0f, botH);
    }
}

- (void)prevSubtuneClicked:(id)sender
{
    if (_playerWindow) {
        [_playerWindow previousSubtune:sender];
    }
}

- (void)nextSubtuneClicked:(id)sender
{
    if (_playerWindow) {
        [_playerWindow nextSubtune:sender];
    }
}

- (void)setPlayerWindow:(SPPlayerWindow *)playerWindow
{
    _playerWindow = playerWindow;
    _vectorScopeView.playerWindow = playerWindow;
    [self updatePlayerState];
}

#pragma mark - Actions

- (void)volumeKnobChanged:(id)sender
{
    if (_playerWindow) {
        float vol = _volumeKnob.knobValue / 100.0f;
        [_playerWindow setPlaybackVolume:vol];
    }
}

- (void)tempoKnobChanged:(id)sender
{
    if (_playerWindow && _playerWindow.player) {
        int tempoPct = (int)_tempoKnob.knobValue;
        [_playerWindow.player setTempo:tempoPct];
    }
}

- (void)filterKnobChanged:(id)sender
{
    // Filter resonance / modulation
}

- (void)playPauseToggled:(id)sender
{
    if (_playerWindow) {
        [_playerWindow clickPlayPauseButton:self];
    }
}

- (void)loopToggled:(id)sender
{
    if (_playerWindow) {
        [_playerWindow toggleLoopMode];
    }
}

- (void)stereoSidToggled:(id)sender
{
    // Dual SID toggle
}

- (void)scopeModeToggled:(id)sender
{
    [_vectorScopeView cycleScopeMode];
}

#pragma mark - State Refresh

- (void)updatePlayerState
{
    if (!_playerWindow) return;
    
    PlayerLibSidplayWrapper *player = _playerWindow.player;
    BOOL isPlaying = [_playerWindow isAudioPlaying];
    
    if (_playPauseToggle.isOn != isPlaying) {
        _playPauseToggle.isOn = isPlaying;
    }
    
    BOOL isLoop = [_playerWindow isRepeatSingleActive];
    if (_loopToggle.isOn != isLoop) {
        _loopToggle.isOn = isLoop;
    }
    
    float curVol = [_playerWindow playbackVolume] * 100.0f;
    if (fabs(_volumeKnob.knobValue - curVol) > 1.0f) {
        _volumeKnob.knobValue = curVol;
    }
    
    int seconds = (player != NULL) ? [player getPlaybackSeconds] : 0;
    [_timeNixieView setTimeInSeconds:seconds];
    
    int curSub = (player != NULL) ? [player getCurrentSubtune] : 1;
    int totalSubs = (player != NULL) ? [player getSubtuneCount] : 1;
    if (totalSubs < 1) totalSubs = 1;
    if (curSub < 1) curSub = 1;
    [_subtuneNixieView setSubtune:curSub count:totalSubs];
    
    if (player != NULL) {
        BOOL isDual = ([player getSidChips] > 1);
        if (_stereoSidToggle.isOn != isDual) {
            _stereoSidToggle.isOn = isDual;
        }
    }
    
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawHexScrewAtPoint:(CGPoint)center inContext:(CGContextRef)ctx
{
    CGFloat outerR = 6.0f;
    NSRect outerRect = NSMakeRect(center.x - outerR, center.y - outerR, outerR * 2.0f, outerR * 2.0f);
    
    NSColor *wTop = [NSColor colorWithCalibratedRed:0.42f green:0.45f blue:0.52f alpha:1.0f];
    NSColor *wBot = [NSColor colorWithCalibratedRed:0.14f green:0.15f blue:0.18f alpha:1.0f];
    NSGradient *wGrad = [[NSGradient alloc] initWithStartingColor:wTop endingColor:wBot];
    [wGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:outerRect] angle:-45.0f];
    
    CGFloat hexR = 3.2f;
    NSBezierPath *hex = [NSBezierPath bezierPath];
    for (int i = 0; i < 6; i++) {
        CGFloat rad = (CGFloat)i * (M_PI / 3.0f);
        CGFloat x = center.x + hexR * cos(rad);
        CGFloat y = center.y + hexR * sin(rad);
        if (i == 0) [hex moveToPoint:NSMakePoint(x, y)];
        else [hex lineToPoint:NSMakePoint(x, y)];
    }
    [hex closePath];
    
    [[NSColor colorWithCalibratedWhite:0.04f alpha:1.0f] setFill];
    [hex fill];
    
    [[NSColor colorWithCalibratedWhite:0.55f alpha:0.8f] setStroke];
    hex.lineWidth = 0.6f;
    [hex stroke];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if (!ctx) return;
    
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    // 1. Brushed Gunmetal Chassis Plate (Deep dark metallic base)
    NSColor *plateTop = [NSColor colorWithCalibratedRed:0.16f green:0.18f blue:0.22f alpha:1.0f];
    NSColor *plateBot = [NSColor colorWithCalibratedRed:0.08f green:0.09f blue:0.11f alpha:1.0f];
    NSGradient *plateGrad = [[NSGradient alloc] initWithStartingColor:plateTop endingColor:plateBot];
    [plateGrad drawInRect:bounds angle:-90.0f];
    
    // Horizontal brushed grain lines
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.025f] setStroke];
    for (CGFloat y = bounds.origin.y + 4.0f; y < bounds.origin.y + h - 4.0f; y += 3.0f) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(bounds.origin.x + 4.0f, y)
                                  toPoint:NSMakePoint(bounds.origin.x + w - 4.0f, y)];
    }
    
    // 2. Beveled Metallic Chassis Perimeter Border
    [[NSColor colorWithCalibratedRed:0.35f green:0.38f blue:0.46f alpha:0.85f] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1.5f, 1.5f) xRadius:5.0f yRadius:5.0f];
    border.lineWidth = 2.0f;
    [border stroke];
    
    // 3. Recessed Control Bays
    // Bay 1: Nixies
    if (!_timeNixieView.isHidden) {
        CGFloat b1X = _timeNixieView.frame.origin.x - 6.0f;
        CGFloat b1Right = _nextSubtuneBtn ? (_nextSubtuneBtn.frame.origin.x + _nextSubtuneBtn.frame.size.width) : (_subtuneNixieView.frame.origin.x + _subtuneNixieView.frame.size.width);
        CGFloat b1W = b1Right - b1X + 6.0f;
        NSRect bay1 = NSMakeRect(b1X, 8.0f, b1W, h - 16.0f);
        [[NSColor colorWithCalibratedRed:0.05f green:0.06f blue:0.08f alpha:0.92f] setFill];
        NSBezierPath *b1Path = [NSBezierPath bezierPathWithRoundedRect:bay1 xRadius:4.0f yRadius:4.0f];
        [b1Path fill];
        [[NSColor colorWithCalibratedRed:0.25f green:0.28f blue:0.34f alpha:0.55f] setStroke];
        b1Path.lineWidth = 1.0f;
        [b1Path stroke];
        
        // Brand Placard Header in Bay 1
        NSRect placardRect = NSMakeRect(bay1.origin.x + 6.0f, bay1.origin.y + bay1.size.height - 28.0f, bay1.size.width - 12.0f, 22.0f);
        [[NSColor colorWithCalibratedRed:0.10f green:0.12f blue:0.15f alpha:0.85f] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:placardRect xRadius:2.0f yRadius:2.0f] fill];
        
        NSString *headerTitle = @"COMMODORE 64 // TIME & SUBTUNE";
        NSFont *headFont = [NSFont monospacedSystemFontOfSize:9.5f weight:NSFontWeightHeavy] ?: [NSFont boldSystemFontOfSize:9.5f] ?: [NSFont systemFontOfSize:9.5f];
        NSMutableDictionary *headAttr = [NSMutableDictionary dictionaryWithCapacity:2];
        if (headFont) headAttr[NSFontAttributeName] = headFont;
        headAttr[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedRed:0.85f green:0.88f blue:0.95f alpha:0.9f];
        [headerTitle drawAtPoint:NSMakePoint(placardRect.origin.x + 6.0f, placardRect.origin.y + 5.0f) withAttributes:headAttr];
        
        // Power/Audio LED dot
        BOOL isPlaying = (_playerWindow != nil) && [_playerWindow isAudioPlaying];
        NSColor *ledColor = isPlaying ? [NSColor colorWithCalibratedRed:0.2f green:1.0f blue:0.4f alpha:1.0f] : [NSColor colorWithCalibratedRed:0.9f green:0.3f blue:0.2f alpha:0.8f];
        [ledColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(placardRect.origin.x + placardRect.size.width - 16.0f, placardRect.origin.y + 6.0f, 8.0f, 8.0f)] fill];
    }
    
    // Bay 2: Knobs Bay
    if (!_volumeKnob.isHidden) {
        CGFloat kBayX = _volumeKnob.frame.origin.x - 6.0f;
        CGFloat kBayW = (_filterKnob.frame.origin.x + _filterKnob.frame.size.width) - kBayX + 6.0f;
        NSRect bay2 = NSMakeRect(kBayX, 8.0f, kBayW, h - 16.0f);
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:0.85f] setFill];
        NSBezierPath *b2Path = [NSBezierPath bezierPathWithRoundedRect:bay2 xRadius:4.0f yRadius:4.0f];
        [b2Path fill];
        [[NSColor colorWithCalibratedRed:0.24f green:0.27f blue:0.32f alpha:0.5f] setStroke];
        b2Path.lineWidth = 1.0f;
        [b2Path stroke];
    }
    
    // Bay 3: Toggles Bay
    if (!_playPauseToggle.isHidden) {
        CGFloat tBayX = _playPauseToggle.frame.origin.x - 6.0f;
        CGFloat tBayW = (_scopeModeToggle.frame.origin.x + _scopeModeToggle.frame.size.width) - tBayX + 6.0f;
        NSRect bay3 = NSMakeRect(tBayX, 8.0f, tBayW, h - 16.0f);
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:0.85f] setFill];
        NSBezierPath *b3Path = [NSBezierPath bezierPathWithRoundedRect:bay3 xRadius:4.0f yRadius:4.0f];
        [b3Path fill];
        [[NSColor colorWithCalibratedRed:0.24f green:0.27f blue:0.32f alpha:0.5f] setStroke];
        b3Path.lineWidth = 1.0f;
        [b3Path stroke];
    }
    
    // 4. Four Corner Hex Socket Cap Screws
    [self drawHexScrewAtPoint:CGPointMake(9.0f, 9.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(w - 9.0f, 9.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(9.0f, h - 9.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(w - 9.0f, h - 9.0f) inContext:ctx];
}

@end
