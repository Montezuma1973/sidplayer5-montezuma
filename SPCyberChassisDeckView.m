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
    NSRect timeRect = NSMakeRect(24.0f, 218.0f, 172.0f, 72.0f);
    _timeNixieView = [[SPNixieDisplayView alloc] initWithFrame:timeRect];
    _timeNixieView.showSubtune = NO;
    [_timeNixieView setTimeInSeconds:0];
    [self addSubview:_timeNixieView];
    
    // 2. Subtune Nixie Display (01/01)
    NSRect subRect = NSMakeRect(204.0f, 218.0f, 120.0f, 72.0f);
    _subtuneNixieView = [[SPNixieDisplayView alloc] initWithFrame:subRect];
    _subtuneNixieView.showSubtune = YES;
    [_subtuneNixieView setSubtune:1 count:1];
    [self addSubview:_subtuneNixieView];
    
    // 3. Circular Phosphor Vector Scope
    NSRect scopeRect = NSMakeRect(348.0f, 170.0f, 175.0f, 175.0f);
    _vectorScopeView = [[SPCircularVectorScopeView alloc] initWithFrame:scopeRect];
    _vectorScopeView.scopeMode = SPVectorScopeModeLissajousXY;
    [self addSubview:_vectorScopeView];
    
    // 4. Knurled Rotary Knobs
    // Volume Knob (0% - 100%)
    NSRect volRect = NSMakeRect(24.0f, 26.0f, 90.0f, 130.0f);
    _volumeKnob = [[SPKnurledKnobControl alloc] initWithFrame:volRect
                                                        title:@"VOLUME"
                                                         unit:@"%"
                                                     minValue:0.0f
                                                     maxValue:100.0f
                                                 initialValue:80.0f
                                                        color:SPKnobColorCyan];
    _volumeKnob.target = self;
    _volumeKnob.action = @selector(volumeKnobChanged:);
    [self addSubview:_volumeKnob];
    
    // Tempo / Pitch Knob (50% - 200%)
    NSRect tempoRect = NSMakeRect(122.0f, 26.0f, 90.0f, 130.0f);
    _tempoKnob = [[SPKnurledKnobControl alloc] initWithFrame:tempoRect
                                                       title:@"TEMPO"
                                                        unit:@"%"
                                                    minValue:50.0f
                                                    maxValue:200.0f
                                                initialValue:100.0f
                                                       color:SPKnobColorAmber];
    _tempoKnob.target = self;
    _tempoKnob.action = @selector(tempoKnobChanged:);
    [self addSubview:_tempoKnob];
    
    // Filter Resonance Knob (0% - 100%)
    NSRect filterRect = NSMakeRect(220.0f, 26.0f, 90.0f, 130.0f);
    _filterKnob = [[SPKnurledKnobControl alloc] initWithFrame:filterRect
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
    // Play / Stop Toggle
    NSRect playRect = NSMakeRect(324.0f, 28.0f, 48.0f, 126.0f);
    _playPauseToggle = [[SPToggleSwitchControl alloc] initWithFrame:playRect
                                                             title:@"PLAY"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorEmerald];
    _playPauseToggle.target = self;
    _playPauseToggle.action = @selector(playPauseToggled:);
    [self addSubview:_playPauseToggle];
    
    // Loop Toggle
    NSRect loopRect = NSMakeRect(378.0f, 28.0f, 48.0f, 126.0f);
    _loopToggle = [[SPToggleSwitchControl alloc] initWithFrame:loopRect
                                                         title:@"LOOP"
                                                          isOn:NO
                                                      ledColor:SPToggleLedColorAmber];
    _loopToggle.target = self;
    _loopToggle.action = @selector(loopToggled:);
    [self addSubview:_loopToggle];
    
    // Stereo / Dual SID Toggle
    NSRect stereoRect = NSMakeRect(432.0f, 28.0f, 48.0f, 126.0f);
    _stereoSidToggle = [[SPToggleSwitchControl alloc] initWithFrame:stereoRect
                                                             title:@"DUAL SID"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorCyan];
    _stereoSidToggle.target = self;
    _stereoSidToggle.action = @selector(stereoSidToggled:);
    [self addSubview:_stereoSidToggle];
    
    // Vector Scope Mode Toggle
    NSRect scopeModeRect = NSMakeRect(486.0f, 28.0f, 48.0f, 126.0f);
    _scopeModeToggle = [[SPToggleSwitchControl alloc] initWithFrame:scopeModeRect
                                                             title:@"SCOPE"
                                                              isOn:NO
                                                          ledColor:SPToggleLedColorAmber];
    _scopeModeToggle.target = self;
    _scopeModeToggle.action = @selector(scopeModeToggled:);
    [self addSubview:_scopeModeToggle];
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
    // Feedback or custom resonance modulation
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
    // Dual SID / Stereo mode toggle
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
    
    // 1. Sync Play/Pause Toggle
    if (_playPauseToggle.isOn != isPlaying) {
        _playPauseToggle.isOn = isPlaying;
    }
    
    // 2. Sync Loop Toggle
    BOOL isLoop = [_playerWindow isRepeatSingleActive];
    if (_loopToggle.isOn != isLoop) {
        _loopToggle.isOn = isLoop;
    }
    
    // 3. Sync Volume Knob
    float curVol = [_playerWindow playbackVolume] * 100.0f;
    if (fabs(_volumeKnob.knobValue - curVol) > 1.0f) {
        _volumeKnob.knobValue = curVol;
    }
    
    // 4. Sync Nixie Time
    int seconds = (player != NULL) ? [player getPlaybackSeconds] : 0;
    [_timeNixieView setTimeInSeconds:seconds];
    
    // 5. Sync Nixie Subtune
    int curSub = (player != NULL) ? [player getCurrentSubtune] : 1;
    int totalSubs = (player != NULL) ? [player getSubtuneCount] : 1;
    if (totalSubs < 1) totalSubs = 1;
    if (curSub < 1) curSub = 1;
    [_subtuneNixieView setSubtune:curSub count:totalSubs];
    
    // 6. Sync Dual SID state
    if (player != NULL) {
        BOOL isDual = ([player getSidChips] > 1);
        if (_stereoSidToggle.isOn != isDual) {
            _stereoSidToggle.isOn = isDual;
        }
    }
}

#pragma mark - Drawing

- (void)drawHexScrewAtPoint:(CGPoint)center inContext:(CGContextRef)ctx
{
    CGFloat outerR = 6.5f;
    NSRect outerRect = NSMakeRect(center.x - outerR, center.y - outerR, outerR * 2.0f, outerR * 2.0f);
    
    // Outer washer bevel
    NSColor *wTop = [NSColor colorWithCalibratedRed:0.42f green:0.45f blue:0.52f alpha:1.0f];
    NSColor *wBot = [NSColor colorWithCalibratedRed:0.14f green:0.15f blue:0.18f alpha:1.0f];
    NSGradient *wGrad = [[NSGradient alloc] initWithStartingColor:wTop endingColor:wBot];
    [wGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:outerRect] angle:-45.0f];
    
    // Hexagonal socket cavity
    CGFloat hexR = 3.5f;
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
    NSColor *plateBot = [NSColor colorWithCalibratedRed:0.09f green:0.10f blue:0.12f alpha:1.0f];
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
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2.0f, 2.0f) xRadius:6.0f yRadius:6.0f];
    border.lineWidth = 2.0f;
    [border stroke];
    
    // Outer drop shadow
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.9f] setStroke];
    NSBezierPath *innerShadow = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 4.0f, 4.0f) xRadius:4.0f yRadius:4.0f];
    innerShadow.lineWidth = 1.0f;
    [innerShadow stroke];
    
    // 3. Recessed Control Bays
    // Bay 1: Nixie Bay (Top Left)
    NSRect bay1 = NSMakeRect(16.0f, 206.0f, 316.0f, 92.0f);
    [[NSColor colorWithCalibratedRed:0.05f green:0.06f blue:0.08f alpha:0.95f] setFill];
    NSBezierPath *b1Path = [NSBezierPath bezierPathWithRoundedRect:bay1 xRadius:4.0f yRadius:4.0f];
    [b1Path fill];
    [[NSColor colorWithCalibratedRed:0.25f green:0.28f blue:0.34f alpha:0.6f] setStroke];
    b1Path.lineWidth = 1.0f;
    [b1Path stroke];
    
    // Bay 2: Rotary Knobs Bay (Bottom Left)
    NSRect bay2 = NSMakeRect(16.0f, 16.0f, 300.0f, 178.0f);
    [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:0.85f] setFill];
    NSBezierPath *b2Path = [NSBezierPath bezierPathWithRoundedRect:bay2 xRadius:4.0f yRadius:4.0f];
    [b2Path fill];
    [[NSColor colorWithCalibratedRed:0.24f green:0.27f blue:0.32f alpha:0.5f] setStroke];
    b2Path.lineWidth = 1.0f;
    [b2Path stroke];
    
    // Bay 3: Toggle Switches Bay (Bottom Right)
    NSRect bay3 = NSMakeRect(320.0f, 16.0f, 218.0f, 146.0f);
    [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:0.85f] setFill];
    NSBezierPath *b3Path = [NSBezierPath bezierPathWithRoundedRect:bay3 xRadius:4.0f yRadius:4.0f];
    [b3Path fill];
    [[NSColor colorWithCalibratedRed:0.24f green:0.27f blue:0.32f alpha:0.5f] setStroke];
    b3Path.lineWidth = 1.0f;
    [b3Path stroke];
    
    // 4. Laser Etched Brand Placard / Header Badge
    NSRect placardRect = NSMakeRect(18.0f, h - 44.0f, 312.0f, 32.0f);
    NSBezierPath *placard = [NSBezierPath bezierPathWithRoundedRect:placardRect xRadius:3.0f yRadius:3.0f];
    [[NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:0.9f] setFill];
    [placard fill];
    [[NSColor colorWithCalibratedRed:0.30f green:0.34f blue:0.40f alpha:0.6f] setStroke];
    placard.lineWidth = 0.8f;
    [placard stroke];
    
    NSString *headerTitle = @"COMMODORE 64 // CYBER-CHASSIS DECK";
    NSDictionary *headAttr = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.0f weight:NSFontWeightHeavy],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.85f green:0.88f blue:0.95f alpha:0.9f]
    };
    [headerTitle drawAtPoint:NSMakePoint(placardRect.origin.x + 8.0f, placardRect.origin.y + 15.0f) withAttributes:headAttr];
    
    NSString *headerSub = @"HARDWARE SYNTHESIZER / RADAR PHOSPHOR SCOPE";
    NSDictionary *subAttr = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:7.5f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.55f green:0.60f blue:0.70f alpha:0.8f]
    };
    [headerSub drawAtPoint:NSMakePoint(placardRect.origin.x + 8.0f, placardRect.origin.y + 4.0f) withAttributes:subAttr];
    
    // Status LEDs on Placard
    CGFloat pwrLedX = placardRect.origin.x + placardRect.size.width - 24.0f;
    CGFloat pwrLedY = placardRect.origin.y + 12.0f;
    NSRect pwrDot = NSMakeRect(pwrLedX, pwrLedY, 8.0f, 8.0f);
    
    BOOL isPlaying = (_playerWindow != nil) && [_playerWindow isAudioPlaying];
    NSColor *ledColor = isPlaying ? [NSColor colorWithCalibratedRed:0.2f green:1.0f blue:0.4f alpha:1.0f] : [NSColor colorWithCalibratedRed:0.9f green:0.3f blue:0.2f alpha:0.8f];
    [ledColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:pwrDot] fill];
    
    // 5. Four Corner Hex Socket Cap Screws
    [self drawHexScrewAtPoint:CGPointMake(12.0f, 12.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(w - 12.0f, 12.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(12.0f, h - 12.0f) inContext:ctx];
    [self drawHexScrewAtPoint:CGPointMake(w - 12.0f, h - 12.0f) inContext:ctx];
}

@end
