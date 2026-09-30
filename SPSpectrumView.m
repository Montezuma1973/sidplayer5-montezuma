#import "SPSpectrumView.h"
#import <math.h>

static const int kSpectrumFFTSize = 1024;
static const int kSpectrumBarCount = 8;
static NSString * const kRetroVisualizerModePrefKey = @"SPVisualizerRetroMode";
static NSString * const kCRTEffectEnabledPrefKey = @"SPVisualizerCRTEffect";
static NSString * const kCRTProfilePrefKey = @"SPVisualizerCRTProfile";

@implementation SPSpectrumView
{
    float _barLevels[kSpectrumBarCount];
    float _window[kSpectrumFFTSize];
    float _real[kSpectrumFFTSize];
    float _imag[kSpectrumFFTSize];
    float _magnitudes[kSpectrumFFTSize / 2];
    BOOL _windowReady;

    // Playback state
    BOOL _isPlaying;
    BOOL _isMod;
    NSTimeInterval _playTime;
    NSTimeInterval _totalTime;
    NSString *_tuneTitle;
    NSString *_chipModel;
    float _audioLevel;
    float _bassLevel;

    // Retro animation variables
    float _ballX;
    float _ballY;
    float _ballVX;
    float _ballVY;
    float _ballRotation;
    float _ballSquash;

    float _reelAngle;
    float _floppyAngle;
    float _driveFlicker;

    // HUD overlay state
    NSTimeInterval _hudDisplayUntil;
    NSString *_hudText;
}

// ----------------------------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frame
// ----------------------------------------------------------------------------
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

// ----------------------------------------------------------------------------
- (instancetype)initWithCoder:(NSCoder *)coder
// ----------------------------------------------------------------------------
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

// ----------------------------------------------------------------------------
- (void)commonInit
// ----------------------------------------------------------------------------
{
    for (int i = 0; i < kSpectrumBarCount; i++) {
        _barLevels[i] = 0.0f;
    }
    _windowReady = NO;
    _isPlaying = NO;
    _isMod = NO;
    _playTime = 0;
    _totalTime = 0;
    _tuneTitle = @"";
    _chipModel = @"MOS 6581";
    _audioLevel = 0.0f;
    _bassLevel = 0.0f;

    _ballX = 120.0f;
    _ballY = 80.0f;
    _ballVX = 2.4f;
    _ballVY = 0.0f;
    _ballRotation = 0.0f;
    _ballSquash = 1.0f;

    _reelAngle = 0.0f;
    _floppyAngle = 0.0f;
    _driveFlicker = 0.0f;

    _hudDisplayUntil = 0;
    _hudText = @"";

    NSInteger savedMode = [[NSUserDefaults standardUserDefaults] integerForKey:kRetroVisualizerModePrefKey];
    if (savedMode < 0 || savedMode > 4) {
        savedMode = SPRetroVisualizerModeAuto;
    }
    _visualizerMode = (SPRetroVisualizerMode)savedMode;

    if ([[NSUserDefaults standardUserDefaults] objectForKey:kCRTEffectEnabledPrefKey] != nil) {
        _crtEffectEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kCRTEffectEnabledPrefKey];
    } else {
        _crtEffectEnabled = YES; // Default CRT monitor filter enabled
    }

    NSInteger savedProfile = [[NSUserDefaults standardUserDefaults] integerForKey:kCRTProfilePrefKey];
    if (savedProfile < 0 || savedProfile > 3) {
        savedProfile = SPCRTDisplayProfile1084SColor;
    }
    _crtProfile = (SPCRTDisplayProfile)savedProfile;

    [self setToolTip:@"Click to switch mode. Double-click to toggle CRT scanlines. Right-click for options."];
}

// ----------------------------------------------------------------------------
- (BOOL)isFlipped
// ----------------------------------------------------------------------------
{
    return YES;
}

// ----------------------------------------------------------------------------
- (BOOL)acceptsFirstResponder
// ----------------------------------------------------------------------------
{
    return YES;
}

// ----------------------------------------------------------------------------
- (void)setVisualizerMode:(SPRetroVisualizerMode)visualizerMode
// ----------------------------------------------------------------------------
{
    _visualizerMode = visualizerMode;
    [[NSUserDefaults standardUserDefaults] setInteger:_visualizerMode forKey:kRetroVisualizerModePrefKey];
    [self showHudForCurrentMode];
    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)cycleVisualizerMode
// ----------------------------------------------------------------------------
{
    SPRetroVisualizerMode nextMode = (SPRetroVisualizerMode)((_visualizerMode + 1) % 5);
    [self setVisualizerMode:nextMode];
}

// ----------------------------------------------------------------------------
- (void)setCrtEffectEnabled:(BOOL)crtEffectEnabled
// ----------------------------------------------------------------------------
{
    _crtEffectEnabled = crtEffectEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:_crtEffectEnabled forKey:kCRTEffectEnabledPrefKey];
    [self showHudForCRTState];
    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)toggleCRTEffect
// ----------------------------------------------------------------------------
{
    [self setCrtEffectEnabled:!_crtEffectEnabled];
}

// ----------------------------------------------------------------------------
- (void)setCrtProfile:(SPCRTDisplayProfile)crtProfile
// ----------------------------------------------------------------------------
{
    _crtProfile = crtProfile;
    [[NSUserDefaults standardUserDefaults] setInteger:_crtProfile forKey:kCRTProfilePrefKey];
    _crtEffectEnabled = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCRTEffectEnabledPrefKey];
    [self showHudForCRTState];
    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)cycleCRTProfile
// ----------------------------------------------------------------------------
{
    SPCRTDisplayProfile nextProfile = (SPCRTDisplayProfile)((_crtProfile + 1) % 4);
    [self setCrtProfile:nextProfile];
}

// ----------------------------------------------------------------------------
- (void)showHudForCurrentMode
// ----------------------------------------------------------------------------
{
    NSString *name = @"";
    switch (_visualizerMode) {
        case SPRetroVisualizerModeAuto:
            name = _isMod ? @"AUTO: AMIGA BOING BALL" : @"AUTO: COMMODORE DATASETTE";
            break;
        case SPRetroVisualizerModeBoingBall:
            name = @"AMIGA BOING BALL (1984)";
            break;
        case SPRetroVisualizerModeCassette:
            name = @"COMMODORE DATASETTE TAPE";
            break;
        case SPRetroVisualizerModeFloppy:
            name = @"COMMODORE 1541 FLOPPY DRIVE";
            break;
        case SPRetroVisualizerModeSpectrum:
            name = @"EQUALIZER SPECTRUM";
            break;
    }
    _hudText = [NSString stringWithFormat:@"%@  •  Click to Switch", name];
    _hudDisplayUntil = [NSDate timeIntervalSinceReferenceDate] + 2.4;
}

// ----------------------------------------------------------------------------
- (void)showHudForCRTState
// ----------------------------------------------------------------------------
{
    if (!_crtEffectEnabled) {
        _hudText = @"CRT MONITOR: OFF";
    } else {
        NSString *profileName = @"1084S COLOR";
        switch (_crtProfile) {
            case SPCRTDisplayProfile1084SColor:
                profileName = @"COMMODORE 1084S COLOR";
                break;
            case SPCRTDisplayProfileAmber:
                profileName = @"AMBER PHOSPHOR";
                break;
            case SPCRTDisplayProfileGreen:
                profileName = @"GREEN PHOSPHOR";
                break;
            case SPCRTDisplayProfileC64Cyan:
                profileName = @"C64 CYAN / BLUE";
                break;
        }
        _hudText = [NSString stringWithFormat:@"CRT MONITOR: %@ (ON)", profileName];
    }
    _hudDisplayUntil = [NSDate timeIntervalSinceReferenceDate] + 2.4;
}

// ----------------------------------------------------------------------------
- (void)mouseDown:(NSEvent *)event
// ----------------------------------------------------------------------------
{
    if ([event clickCount] == 2) {
        [self toggleCRTEffect];
    } else {
        [self cycleVisualizerMode];
    }
}

// ----------------------------------------------------------------------------
- (void)keyDown:(NSEvent *)event
// ----------------------------------------------------------------------------
{
    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars isEqualToString:@"c"] || [chars isEqualToString:@"C"]) {
        [self toggleCRTEffect];
    } else if ([chars isEqualToString:@"p"] || [chars isEqualToString:@"P"]) {
        [self cycleCRTProfile];
    } else if ([chars isEqualToString:@"v"] || [chars isEqualToString:@"V"]) {
        [self cycleVisualizerMode];
    } else {
        [super keyDown:event];
    }
}

// ----------------------------------------------------------------------------
- (NSMenu *)menuForEvent:(NSEvent *)event
// ----------------------------------------------------------------------------
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Retro Visualizer"];

    NSArray *titles = @[
        @"Auto (Amiga MOD / C64 SID)",
        @"Amiga Boing Ball (1984 Demo)",
        @"Commodore Datasette (C-60 Tape)",
        @"Commodore 1541 (5.25\" Floppy)",
        @"Equalizer Spectrum Bars"
    ];

    for (NSInteger i = 0; i < 5; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i]
                                                      action:@selector(selectModeFromMenu:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = i;
        if (i == (NSInteger)_visualizerMode) {
            item.state = NSControlStateValueOn;
        }
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // CRT Monitor Submenu
    NSMenuItem *crtSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"CRT Monitor & Scanlines" action:nil keyEquivalent:@""];
    NSMenu *crtSubmenu = [[NSMenu alloc] initWithTitle:@"CRT Monitor"];

    NSMenuItem *toggleCRTItem = [[NSMenuItem alloc] initWithTitle:@"Enable CRT Scanlines & Glass"
                                                           action:@selector(toggleCRTEffect)
                                                    keyEquivalent:@"c"];
    toggleCRTItem.target = self;
    if (_crtEffectEnabled) {
        toggleCRTItem.state = NSControlStateValueOn;
    }
    [crtSubmenu addItem:toggleCRTItem];
    [crtSubmenu addItem:[NSMenuItem separatorItem]];

    NSArray *profiles = @[
        @"Commodore 1084S (Color RGB)",
        @"Amber Phosphor (Monochrome)",
        @"Green Phosphor (Monochrome)",
        @"C64 Cyan / Blue Phosphor"
    ];

    for (NSInteger p = 0; p < 4; p++) {
        NSMenuItem *pItem = [[NSMenuItem alloc] initWithTitle:profiles[p]
                                                       action:@selector(selectProfileFromMenu:)
                                                keyEquivalent:@""];
        pItem.target = self;
        pItem.tag = p;
        if (_crtEffectEnabled && p == (NSInteger)_crtProfile) {
            pItem.state = NSControlStateValueOn;
        }
        [crtSubmenu addItem:pItem];
    }

    [crtSubmenuItem setSubmenu:crtSubmenu];
    [menu addItem:crtSubmenuItem];

    return menu;
}

// ----------------------------------------------------------------------------
- (void)selectModeFromMenu:(NSMenuItem *)sender
// ----------------------------------------------------------------------------
{
    [self setVisualizerMode:(SPRetroVisualizerMode)sender.tag];
}

// ----------------------------------------------------------------------------
- (void)selectProfileFromMenu:(NSMenuItem *)sender
// ----------------------------------------------------------------------------
{
    [self setCrtProfile:(SPCRTDisplayProfile)sender.tag];
}

// ----------------------------------------------------------------------------
static void SPComputeHannWindow(float *window, int size)
// ----------------------------------------------------------------------------
{
    const float twoPi = 2.0f * (float)M_PI;
    for (int i = 0; i < size; i++) {
        window[i] = 0.5f * (1.0f - cosf(twoPi * (float)i / (float)(size - 1)));
    }
}

// ----------------------------------------------------------------------------
static void SPFFT(float *real, float *imag, int size)
// ----------------------------------------------------------------------------
{
    int j = 0;
    for (int i = 1; i < size; i++) {
        int bit = size >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            float temp = real[i];
            real[i] = real[j];
            real[j] = temp;
            temp = imag[i];
            imag[i] = imag[j];
            imag[j] = temp;
        }
    }

    for (int len = 2; len <= size; len <<= 1) {
        float angle = -2.0f * (float)M_PI / (float)len;
        float wlenCos = cosf(angle);
        float wlenSin = sinf(angle);
        for (int i = 0; i < size; i += len) {
            float wCos = 1.0f;
            float wSin = 0.0f;
            int half = len >> 1;
            for (int j2 = 0; j2 < half; j2++) {
                int u = i + j2;
                int v = u + half;
                float realV = real[v] * wCos - imag[v] * wSin;
                float imagV = real[v] * wSin + imag[v] * wCos;
                real[v] = real[u] - realV;
                imag[v] = imag[u] - imagV;
                real[u] += realV;
                imag[u] += imagV;
                float nextCos = wCos * wlenCos - wSin * wlenSin;
                float nextSin = wCos * wlenSin + wSin * wlenCos;
                wCos = nextCos;
                wSin = nextSin;
            }
        }
    }
}

// ----------------------------------------------------------------------------
- (void)updateWithSamples:(const short *)samples count:(int)count sampleRate:(int)sampleRate
// ----------------------------------------------------------------------------
{
    if (samples == NULL || count <= 0) {
        return;
    }

    if (!_windowReady) {
        SPComputeHannWindow(_window, kSpectrumFFTSize);
        _windowReady = YES;
    }

    int copyCount = count >= kSpectrumFFTSize ? kSpectrumFFTSize : count;
    int startIndex = count - copyCount;

    float sumSquares = 0.0f;
    for (int i = 0; i < kSpectrumFFTSize; i++) {
        float sample = 0.0f;
        if (i < copyCount) {
            sample = (float)samples[startIndex + i] / 32768.0f;
            sumSquares += sample * sample;
        }
        _real[i] = sample * _window[i];
        _imag[i] = 0.0f;
    }

    float rawRms = sqrtf(sumSquares / (float)(copyCount > 0 ? copyCount : 1));
    float targetLevel = rawRms * 3.8f;
    if (targetLevel > 1.0f) targetLevel = 1.0f;
    _audioLevel = _audioLevel * 0.75f + targetLevel * 0.25f;

    SPFFT(_real, _imag, kSpectrumFFTSize);

    for (int i = 0; i < kSpectrumFFTSize / 2; i++) {
        float real = _real[i];
        float imag = _imag[i];
        _magnitudes[i] = sqrtf(real * real + imag * imag);
    }

    float nyquist = (float)sampleRate * 0.5f;
    float minFreq = 31.0f;
    float maxFreq = nyquist < 12000.0f ? nyquist : 12000.0f;

    for (int i = 0; i < kSpectrumBarCount; i++) {
        float low = minFreq * powf(2.0f, (float)i);
        float high = low * 2.0f;
        if (low >= maxFreq) {
            _barLevels[i] = 0.0f;
            continue;
        }
        if (high > maxFreq) {
            high = maxFreq;
        }
        int lowBin = (int)floorf(low * (float)kSpectrumFFTSize / (float)sampleRate);
        int highBin = (int)floorf(high * (float)kSpectrumFFTSize / (float)sampleRate);

        if (lowBin < 1) {
            lowBin = 1;
        }
        if (highBin <= lowBin) {
            highBin = lowBin + 1;
        }
        int maxBin = (kSpectrumFFTSize / 2) - 1;
        if (highBin > maxBin) {
            highBin = maxBin;
        }

        float sum = 0.0f;
        int bins = highBin - lowBin + 1;
        for (int bin = lowBin; bin <= highBin; bin++) {
            sum += _magnitudes[bin];
        }
        float avg = sum / (float)bins;
        avg /= (float)kSpectrumFFTSize;
        float db = 20.0f * log10f(avg + 1e-9f);
        float normalized = (db + 90.0f) / 80.0f;
        if (normalized < 0.0f) {
            normalized = 0.0f;
        } else if (normalized > 1.0f) {
            normalized = 1.0f;
        }

        if (normalized > _barLevels[i]) {
            _barLevels[i] = normalized;
        } else {
            _barLevels[i] = _barLevels[i] * 0.85f + normalized * 0.15f;
        }
    }

    float rawBass = (_barLevels[0] * 0.65f + _barLevels[1] * 0.35f);
    _bassLevel = _bassLevel * 0.80f + rawBass * 0.20f;

    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)updatePlaybackState:(BOOL)isPlaying
                      isMod:(BOOL)isMod
                   playTime:(NSTimeInterval)playTime
                  totalTime:(NSTimeInterval)totalTime
                  tuneTitle:(NSString *)tuneTitle
// ----------------------------------------------------------------------------
{
    [self updatePlaybackState:isPlaying
                        isMod:isMod
                     playTime:playTime
                    totalTime:totalTime
                    tuneTitle:tuneTitle
                    chipModel:isMod ? @"PAULA 8364" : _chipModel];
}

// ----------------------------------------------------------------------------
- (void)updatePlaybackState:(BOOL)isPlaying
                      isMod:(BOOL)isMod
                   playTime:(NSTimeInterval)playTime
                  totalTime:(NSTimeInterval)totalTime
                  tuneTitle:(NSString *)tuneTitle
                  chipModel:(NSString *)chipModel
// ----------------------------------------------------------------------------
{
    _isPlaying = isPlaying;
    _isMod = isMod;
    _playTime = playTime;
    _totalTime = totalTime;
    _tuneTitle = tuneTitle ? [tuneTitle copy] : @"";
    if (chipModel != nil && [chipModel length] > 0) {
        _chipModel = [chipModel copy];
    }

    NSRect bounds = self.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    if (width <= 0 || height <= 0) return;

    float ballRadius = MIN(width * 0.24f, height * 0.24f);
    if (ballRadius < 35.0f) ballRadius = 35.0f;
    if (ballRadius > 70.0f) ballRadius = 70.0f;

    float xMin = ballRadius + 10.0f;
    float xMax = width - ballRadius - 10.0f;
    float yFloor = height - ballRadius - 12.0f;

    if (_isPlaying) {
        // Advance Boing Ball physics
        _ballX += _ballVX;
        if (_ballX < xMin) {
            _ballX = xMin;
            _ballVX = fabsf(_ballVX);
        } else if (_ballX > xMax) {
            _ballX = xMax;
            _ballVX = -fabsf(_ballVX);
        }

        _ballVY += 0.58f; // gravity
        _ballY += _ballVY;
        if (_ballY >= yFloor) {
            _ballY = yFloor;
            _ballVY = -fabsf(_ballVY) * 0.96f;
            if (fabsf(_ballVY) < 8.5f) {
                _ballVY = -11.0f - _bassLevel * 3.5f;
            }
            _ballSquash = 0.72f - _bassLevel * 0.12f;
        }
        _ballRotation += 0.055f;

        // Advance Cassette and Floppy rotations
        _reelAngle += 0.065f;
        _floppyAngle += 0.080f;

        // Drive flicker activity
        if (_audioLevel > 0.06f) {
            _driveFlicker = 1.0f;
        } else {
            _driveFlicker = _driveFlicker * 0.85f;
        }
    } else {
        // When stopped, gently rest
        _ballSquash = _ballSquash * 0.92f + 1.0f * 0.08f;
        _ballVY = 0.0f;
        _ballY = _ballY * 0.95f + (yFloor - 8.0f) * 0.05f;
        _driveFlicker = _driveFlicker * 0.80f;
    }

    _ballSquash += (1.0f - _ballSquash) * 0.16f;

    [self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect
// ----------------------------------------------------------------------------
{
    NSRect bounds = self.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return;

    SPRetroVisualizerMode effectiveMode = _visualizerMode;
    if (effectiveMode == SPRetroVisualizerModeAuto) {
        effectiveMode = _isMod ? SPRetroVisualizerModeBoingBall : SPRetroVisualizerModeCassette;
    }

    switch (effectiveMode) {
        case SPRetroVisualizerModeBoingBall:
            [self drawBoingBallInRect:bounds];
            break;
        case SPRetroVisualizerModeCassette:
            [self drawCassetteInRect:bounds];
            break;
        case SPRetroVisualizerModeFloppy:
            [self drawFloppyInRect:bounds];
            break;
        case SPRetroVisualizerModeSpectrum:
        default:
            [self drawSpectrumInRect:bounds];
            break;
    }

    // Render CRT scanlines & glass filter if enabled
    if (_crtEffectEnabled) {
        [self drawCRTOverlayInRect:bounds];
    }

    // Render HUD overlay if active
    if ([NSDate timeIntervalSinceReferenceDate] < _hudDisplayUntil && [_hudText length] > 0) {
        [self drawHudOverlayInRect:bounds];
    }
}

// ============================================================================
#pragma mark - Hardware Silicon Chip Badge Rendering
// ============================================================================

- (void)drawSiliconChipBadgeInRect:(NSRect)badgeRect model:(NSString *)model isMod:(BOOL)isMod
{
    if (model == nil || [model length] == 0) return;

    // 1. Ceramic DIP IC package body
    NSBezierPath *badgePath = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:3.5f yRadius:3.5f];
    [[NSColor colorWithDeviceRed:0.12f green:0.13f blue:0.16f alpha:0.92f] setFill];
    [badgePath fill];

    // Metallic package border
    [[NSColor colorWithDeviceRed:0.40f green:0.42f blue:0.48f alpha:0.75f] setStroke];
    [badgePath setLineWidth:1.0f];
    [badgePath stroke];

    // 2. Silver DIP dual-inline pins along top and bottom
    [[NSColor colorWithDeviceRed:0.75f green:0.77f blue:0.84f alpha:0.85f] setFill];
    int numPins = (int)(badgeRect.size.width / 16.0f);
    if (numPins < 3) numPins = 3;
    CGFloat pinSpacing = (badgeRect.size.width - 24.0f) / (CGFloat)(numPins - 1);
    for (int p = 0; p < numPins; p++) {
        CGFloat pinX = badgeRect.origin.x + 14.0f + (CGFloat)p * pinSpacing;
        NSRectFill(NSMakeRect(pinX, badgeRect.origin.y - 1.5f, 3.5f, 2.0f));
        NSRectFill(NSMakeRect(pinX, badgeRect.origin.y + badgeRect.size.height - 0.5f, 3.5f, 2.0f));
    }

    // 3. Pin-1 semicircular notch on left edge
    NSBezierPath *notch = [NSBezierPath bezierPath];
    [notch appendBezierPathWithArcWithCenter:NSMakePoint(badgeRect.origin.x, badgeRect.origin.y + badgeRect.size.height * 0.5f)
                                     radius:2.5f
                                 startAngle:-90.0
                                   endAngle:90.0];
    [[NSColor colorWithDeviceRed:0.25f green:0.27f blue:0.30f alpha:1.0f] setFill];
    [notch fill];

    // 4. Status Illuminated LED dot
    NSRect ledRect = NSMakeRect(badgeRect.origin.x + 6.0f, badgeRect.origin.y + (badgeRect.size.height - 5.0f) * 0.5f, 5.0f, 5.0f);
    NSColor *ledColor = nil;
    if (isMod) {
        ledColor = [NSColor colorWithDeviceRed:1.0f green:0.62f blue:0.10f alpha:1.0f]; // Amber for Paula
    } else if ([model containsString:@"8580"]) {
        ledColor = [NSColor colorWithDeviceRed:0.10f green:0.85f blue:1.0f alpha:1.0f]; // Electric Cyan for 8580
    } else {
        ledColor = [NSColor colorWithDeviceRed:0.20f green:0.95f blue:0.35f alpha:1.0f]; // Emerald Green for 6581
    }

    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSShadow *ledGlow = [[NSShadow alloc] init];
    ledGlow.shadowColor = ledColor;
    ledGlow.shadowBlurRadius = 4.0f;
    ledGlow.shadowOffset = NSMakeSize(0, 0);
    [ledGlow set];
    [ledColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];
    [ctx restoreGraphicsState];

    // 5. Laser-etched metallic chip text
    NSDictionary *badgeFontAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:MIN(8.5f, badgeRect.size.height * 0.48f)],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.92f green:0.94f blue:0.98f alpha:1.0f]
    };
    [model drawAtPoint:NSMakePoint(badgeRect.origin.x + 14.5f, badgeRect.origin.y + (badgeRect.size.height - 11.0f) * 0.5f) withAttributes:badgeFontAttr];
}

// ============================================================================
#pragma mark - Amiga Boing Ball Rendering
// ============================================================================

- (void)drawBoingBallInRect:(NSRect)bounds
{
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;

    // 1. Retro Background Gradient (deep demo violet / twilight)
    NSGradient *bgGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithDeviceRed:0.08f green:0.04f blue:0.16f alpha:1.0f],
        [NSColor colorWithDeviceRed:0.18f green:0.08f blue:0.28f alpha:1.0f]
    ]];
    [bgGradient drawInRect:bounds angle:-90.0f];

    CGFloat horizonY = height * 0.38f;

    // 2. Back Wall Grid Lines (Purple)
    [[NSColor colorWithDeviceRed:0.62f green:0.26f blue:0.80f alpha:0.45f] setStroke];
    NSBezierPath *backGrid = [NSBezierPath bezierPath];
    [backGrid setLineWidth:1.0f];

    CGFloat gridSpacingX = 26.0f;
    for (CGFloat x = fmodf(width, gridSpacingX) * 0.5f; x <= width; x += gridSpacingX) {
        [backGrid moveToPoint:NSMakePoint(x, 0)];
        [backGrid lineToPoint:NSMakePoint(x, horizonY)];
    }
    CGFloat gridSpacingY = 20.0f;
    for (CGFloat y = 10.0f; y <= horizonY; y += gridSpacingY) {
        [backGrid moveToPoint:NSMakePoint(0, y)];
        [backGrid lineToPoint:NSMakePoint(width, y)];
    }
    [backGrid stroke];

    // Horizon line
    [[NSColor colorWithDeviceRed:0.85f green:0.45f blue:1.0f alpha:0.85f] setStroke];
    NSBezierPath *horizonLine = [NSBezierPath bezierPath];
    [horizonLine setLineWidth:1.5f];
    [horizonLine moveToPoint:NSMakePoint(0, horizonY)];
    [horizonLine lineToPoint:NSMakePoint(width, horizonY)];
    [horizonLine stroke];

    // 3. Floor Perspective Grid (converging to vanishing point at horizon)
    NSPoint vp = NSMakePoint(width * 0.5f, horizonY);
    NSBezierPath *floorGrid = [NSBezierPath bezierPath];
    [floorGrid setLineWidth:1.0f];
    [[NSColor colorWithDeviceRed:0.58f green:0.22f blue:0.75f alpha:0.50f] setStroke];

    // Radial perspective lines
    int numRays = 16;
    for (int i = 0; i <= numRays; i++) {
        CGFloat xBottom = (CGFloat)i / (CGFloat)numRays * (width * 1.6f) - (width * 0.3f);
        [floorGrid moveToPoint:vp];
        [floorGrid lineToPoint:NSMakePoint(xBottom, height)];
    }

    // Horizontal perspective lines (spaced non-linearly)
    int numHoriz = 9;
    for (int i = 1; i <= numHoriz; i++) {
        float t = (float)i / (float)numHoriz;
        float y = horizonY + (height - horizonY) * (t * t);
        [floorGrid moveToPoint:NSMakePoint(0, y)];
        [floorGrid lineToPoint:NSMakePoint(width, y)];
    }
    [floorGrid stroke];

    // 4. Ball Radius and Floor Placement
    float radius = MIN(width * 0.24f, height * 0.24f);
    if (radius < 35.0f) radius = 35.0f;
    if (radius > 70.0f) radius = 70.0f;

    float yFloor = height - radius - 12.0f;
    if (_ballX < radius) _ballX = radius + 15.0f;
    if (_ballY < radius) _ballY = radius + 15.0f;

    // 5. Floor Shadow
    float heightAboveFloor = yFloor - _ballY;
    if (heightAboveFloor < 0) heightAboveFloor = 0;
    float heightRatio = heightAboveFloor / (yFloor - radius);
    if (heightRatio > 1.0f) heightRatio = 1.0f;

    float shadowW = radius * (1.60f + 0.35f * heightRatio);
    float shadowH = radius * (0.32f + 0.15f * heightRatio);
    float shadowAlpha = 0.65f * (1.0f - 0.55f * heightRatio);
    NSRect shadowRect = NSMakeRect(_ballX - shadowW * 0.5f,
                                   yFloor + radius * 0.65f - shadowH * 0.5f,
                                   shadowW, shadowH);
    [[NSColor colorWithDeviceRed:0.04f green:0.01f blue:0.08f alpha:shadowAlpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:shadowRect] fill];

    // 6. 3D Checkered Sphere Rendering
    const int numLat = 12;
    const int numLon = 16;
    typedef struct {
        float x, y, z;
        float u, v;
    } Point3D;

    Point3D grid[numLat + 1][numLon + 1];

    float squashY = _ballSquash;
    if (squashY < 0.40f) squashY = 0.40f;
    if (squashY > 1.30f) squashY = 1.30f;
    float squashXZ = 1.0f / sqrtf(squashY);

    const float tiltZ = 0.38f; // ~22 degrees tilt
    const float tiltX = 0.18f; // ~10 degrees tilt forward
    const float cosZ = cosf(tiltZ), sinZ = sinf(tiltZ);
    const float cosX = cosf(tiltX), sinX = sinf(tiltX);
    const float D = 3.6f;

    for (int i = 0; i <= numLat; i++) {
        float phi = - (float)M_PI * 0.5f + (float)M_PI * ((float)i / (float)numLat);
        float cosPhi = cosf(phi);
        float sinPhi = sinf(phi);

        for (int j = 0; j <= numLon; j++) {
            float theta = 2.0f * (float)M_PI * ((float)j / (float)numLon) + _ballRotation;
            float cosTheta = cosf(theta);
            float sinTheta = sinf(theta);

            // Unit sphere coordinates
            float x0 = cosPhi * sinTheta;
            float y0 = sinPhi;
            float z0 = cosPhi * cosTheta;

            // Tilt around Z
            float x1 = x0 * cosZ - y0 * sinZ;
            float y1 = x0 * sinZ + y0 * cosZ;
            float z1 = z0;

            // Tilt around X
            float x2 = x1;
            float y2 = y1 * cosX - z1 * sinX;
            float z2 = y1 * sinX + z1 * cosX;

            grid[i][j].x = x2;
            grid[i][j].y = y2;
            grid[i][j].z = z2;

            // Squash & stretch
            float x3 = x2 * squashXZ;
            float y3 = y2 * squashY;
            float z3 = z2 * squashXZ;

            // Perspective projection
            float scale = radius * (D / (D + z3));
            grid[i][j].u = _ballX + x3 * scale;
            grid[i][j].v = _ballY + y3 * scale;
        }
    }

    // Directional light vector (top-left, pointing toward screen)
    float lx = -0.42f, ly = -0.55f, lz = 0.72f;
    float lLen = sqrtf(lx * lx + ly * ly + lz * lz);
    lx /= lLen; ly /= lLen; lz /= lLen;

    // Draw front-facing quads
    for (int i = 0; i < numLat; i++) {
        for (int j = 0; j < numLon; j++) {
            Point3D p00 = grid[i][j];
            Point3D p10 = grid[i + 1][j];
            Point3D p11 = grid[i + 1][j + 1];
            Point3D p01 = grid[i][j + 1];

            float avgZ = (p00.z + p10.z + p11.z + p01.z) * 0.25f;
            if (avgZ <= -0.05f) {
                continue; // Backface culling
            }

            // Normal vector at quad center
            float nx = (p00.x + p10.x + p11.x + p01.x) * 0.25f;
            float ny = (p00.y + p10.y + p11.y + p01.y) * 0.25f;
            float nz = (p00.z + p10.z + p11.z + p01.z) * 0.25f;
            float nLen = sqrtf(nx * nx + ny * ny + nz * nz);
            if (nLen > 0.001f) {
                nx /= nLen; ny /= nLen; nz /= nLen;
            }

            float dot = nx * lx + ny * ly + nz * lz;
            if (dot < 0.0f) dot = 0.0f;
            float lighting = 0.32f + 0.68f * dot;

            BOOL isRed = ((i + j) % 2 == 0);
            NSColor *tileColor;
            if (isRed) {
                tileColor = [NSColor colorWithDeviceRed:(0.92f * lighting)
                                                  green:(0.14f * lighting)
                                                   blue:(0.18f * lighting)
                                                  alpha:1.0f];
            } else {
                tileColor = [NSColor colorWithDeviceRed:(0.95f * lighting)
                                                  green:(0.95f * lighting)
                                                   blue:(0.95f * lighting)
                                                  alpha:1.0f];
            }

            NSBezierPath *quad = [NSBezierPath bezierPath];
            [quad moveToPoint:NSMakePoint(p00.u, p00.v)];
            [quad lineToPoint:NSMakePoint(p10.u, p10.v)];
            [quad lineToPoint:NSMakePoint(p11.u, p11.v)];
            [quad lineToPoint:NSMakePoint(p01.u, p01.v)];
            [quad closePath];

            [tileColor setFill];
            [quad fill];

            // Subtle dark seam line between facets
            [[NSColor colorWithDeviceRed:0.25f green:0.05f blue:0.15f alpha:0.35f] setStroke];
            [quad setLineWidth:0.5f];
            [quad stroke];
        }
    }

    // 7. Vintage Amiga Badge in upper left corner
    NSRect badgeRect = NSMakeRect(12.0f, 10.0f, 136.0f, 22.0f);
    NSBezierPath *badgePath = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:5.0f yRadius:5.0f];
    [[NSColor colorWithDeviceRed:0.06f green:0.04f blue:0.10f alpha:0.75f] setFill];
    [badgePath fill];
    [[NSColor colorWithDeviceRed:0.75f green:0.30f blue:0.90f alpha:0.60f] setStroke];
    [badgePath setLineWidth:1.0f];
    [badgePath stroke];

    // Amiga rainbow stripes
    NSArray *rainbowColors = @[
        [NSColor colorWithDeviceRed:0.90f green:0.20f blue:0.20f alpha:1.0f],
        [NSColor colorWithDeviceRed:0.95f green:0.60f blue:0.15f alpha:1.0f],
        [NSColor colorWithDeviceRed:0.95f green:0.90f blue:0.20f alpha:1.0f],
        [NSColor colorWithDeviceRed:0.25f green:0.80f blue:0.30f alpha:1.0f],
        [NSColor colorWithDeviceRed:0.20f green:0.60f blue:0.90f alpha:1.0f]
    ];
    CGFloat stripeX = 18.0f;
    for (int i = 0; i < 5; i++) {
        [(NSColor *)rainbowColors[i] setFill];
        NSRectFill(NSMakeRect(stripeX, 15.0f, 2.5f, 12.0f));
        stripeX += 3.5f;
    }

    NSDictionary *badgeAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9.5f],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    [@"AMIGA BOING" drawAtPoint:NSMakePoint(40.0f, 14.5f) withAttributes:badgeAttr];

    // Hardware silicon chip badge in upper right corner
    NSRect chipRect = NSMakeRect(width - 100.0f, 10.0f, 88.0f, 20.0f);
    [self drawSiliconChipBadgeInRect:chipRect model:(_chipModel ?: @"PAULA 8364") isMod:YES];
}

// ============================================================================
#pragma mark - Commodore Datasette Cassette Tape Rendering
// ============================================================================

- (void)drawCassetteInRect:(NSRect)bounds
{
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;

    // Dark retro desk background
    [[NSColor colorWithDeviceRed:0.11f green:0.11f blue:0.13f alpha:1.0f] setFill];
    NSRectFill(bounds);

    CGFloat cassetteW = MIN(width * 0.90f, height * 1.55f);
    if (cassetteW < 180.0f) cassetteW = 180.0f;
    CGFloat cassetteH = cassetteW / 1.58f;
    CGFloat originX = (width - cassetteW) * 0.5f;
    CGFloat originY = (height - cassetteH) * 0.5f;
    NSRect cassetteRect = NSMakeRect(originX, originY, cassetteW, cassetteH);

    // 1. Outer Cassette Shell
    NSBezierPath *shellPath = [NSBezierPath bezierPathWithRoundedRect:cassetteRect xRadius:10.0f yRadius:10.0f];
    [[NSColor colorWithDeviceRed:0.16f green:0.17f blue:0.19f alpha:1.0f] setFill];
    [shellPath fill];
    [[NSColor colorWithDeviceRed:0.28f green:0.30f blue:0.34f alpha:1.0f] setStroke];
    [shellPath setLineWidth:1.5f];
    [shellPath stroke];

    // Corner Screws
    CGFloat screwInset = cassetteW * 0.045f;
    NSPoint screws[4] = {
        NSMakePoint(originX + screwInset, originY + screwInset),
        NSMakePoint(originX + cassetteW - screwInset, originY + screwInset),
        NSMakePoint(originX + screwInset, originY + cassetteH - screwInset),
        NSMakePoint(originX + cassetteW - screwInset, originY + cassetteH - screwInset)
    };
    for (int i = 0; i < 4; i++) {
        NSRect screwR = NSMakeRect(screws[i].x - 3.5f, screws[i].y - 3.5f, 7.0f, 7.0f);
        [[NSColor colorWithDeviceRed:0.48f green:0.50f blue:0.54f alpha:1.0f] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:screwR] fill];
        [[NSColor colorWithDeviceRed:0.25f green:0.26f blue:0.28f alpha:1.0f] setStroke];
        NSBezierPath *screwSlot = [NSBezierPath bezierPath];
        [screwSlot setLineWidth:1.0f];
        [screwSlot moveToPoint:NSMakePoint(screwR.origin.x + 1.0f, screwR.origin.y + 3.5f)];
        [screwSlot lineToPoint:NSMakePoint(screwR.origin.x + 6.0f, screwR.origin.y + 3.5f)];
        [screwSlot stroke];
    }

    // 2. Vintage Cream Label Area
    CGFloat labelW = cassetteW * 0.88f;
    CGFloat labelH = cassetteH * 0.62f;
    CGFloat labelX = originX + (cassetteW - labelW) * 0.5f;
    CGFloat labelY = originY + cassetteH * 0.12f;
    NSRect labelRect = NSMakeRect(labelX, labelY, labelW, labelH);
    NSBezierPath *labelPath = [NSBezierPath bezierPathWithRoundedRect:labelRect xRadius:6.0f yRadius:6.0f];
    [[NSColor colorWithDeviceRed:0.95f green:0.93f blue:0.86f alpha:1.0f] setFill];
    [labelPath fill];
    [[NSColor colorWithDeviceRed:0.78f green:0.75f blue:0.68f alpha:1.0f] setStroke];
    [labelPath setLineWidth:1.0f];
    [labelPath stroke];

    // Commodore 5-color Rainbow Stripe across the top of label
    NSArray *c64Rainbow = @[
        [NSColor colorWithDeviceRed:0.85f green:0.20f blue:0.20f alpha:1.0f], // Red
        [NSColor colorWithDeviceRed:0.95f green:0.55f blue:0.15f alpha:1.0f], // Orange
        [NSColor colorWithDeviceRed:0.95f green:0.85f blue:0.20f alpha:1.0f], // Yellow
        [NSColor colorWithDeviceRed:0.25f green:0.75f blue:0.35f alpha:1.0f], // Green
        [NSColor colorWithDeviceRed:0.20f green:0.55f blue:0.85f alpha:1.0f]  // Blue
    ];
    CGFloat stripeH = 3.0f;
    CGFloat startStripeY = labelY + 6.0f;
    for (int i = 0; i < 5; i++) {
        [(NSColor *)c64Rainbow[i] setFill];
        NSRectFill(NSMakeRect(labelX + 8.0f, startStripeY + (CGFloat)i * stripeH, labelW - 16.0f, stripeH));
    }

    // Label Header Text
    NSDictionary *c64FontAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:MIN(11.0f, labelW * 0.050f)],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.12f green:0.25f blue:0.48f alpha:1.0f]
    };
    [@"COMMODORE 64" drawAtPoint:NSMakePoint(labelX + 10.0f, labelY + 24.0f) withAttributes:c64FontAttr];

    NSDictionary *sideFontAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:MIN(10.0f, labelW * 0.045f)],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.30f green:0.30f blue:0.32f alpha:1.0f]
    };
    [@"SIDE A  C-60" drawAtPoint:NSMakePoint(labelX + labelW - 75.0f, labelY + 24.0f) withAttributes:sideFontAttr];

    // Current Tune Name on Cassette Label
    NSString *displayTitle = (_tuneTitle && [_tuneTitle length] > 0) ? _tuneTitle : @"COMMODORE 64 SID TUNE";
    NSDictionary *titleAttr = @{
        NSFontAttributeName: [NSFont fontWithName:@"Courier-Bold" size:MIN(11.0f, labelW * 0.048f)] ?: [NSFont boldSystemFontOfSize:10.0f],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.18f green:0.16f blue:0.22f alpha:1.0f]
    };
    NSRect titleBound = NSMakeRect(labelX + 12.0f, labelY + 40.0f, labelW - 24.0f, 16.0f);
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *centerTitleAttr = [titleAttr mutableCopy];
    centerTitleAttr[NSParagraphStyleAttributeName] = style;
    [displayTitle drawInRect:titleBound withAttributes:centerTitleAttr];

    // 3. Center Cassette Acrylic Window
    CGFloat windowW = labelW * 0.68f;
    CGFloat windowH = labelH * 0.42f;
    CGFloat windowX = labelX + (labelW - windowW) * 0.5f;
    CGFloat windowY = labelY + labelH * 0.52f;
    NSRect windowRect = NSMakeRect(windowX, windowY, windowW, windowH);
    NSBezierPath *windowPath = [NSBezierPath bezierPathWithRoundedRect:windowRect xRadius:5.0f yRadius:5.0f];
    [[NSColor colorWithDeviceRed:0.08f green:0.09f blue:0.10f alpha:0.95f] setFill];
    [windowPath fill];
    [[NSColor colorWithDeviceRed:0.25f green:0.26f blue:0.28f alpha:1.0f] setStroke];
    [windowPath setLineWidth:1.5f];
    [windowPath stroke];

    // 4. Dual Tape Spools & Reels
    CGFloat leftHubX = windowX + windowW * 0.28f;
    CGFloat rightHubX = windowX + windowW * 0.72f;
    CGFloat hubY = windowY + windowH * 0.50f;

    CGFloat hubRadius = windowH * 0.30f;
    CGFloat maxTapeRadius = windowH * 0.48f;

    float progress = 0.35f;
    if (_totalTime > 0.0) {
        progress = (float)(_playTime / _totalTime);
        if (progress < 0.05f) progress = 0.05f;
        if (progress > 0.95f) progress = 0.95f;
    }

    // Tape pack radii based on progress
    float leftTapeR = sqrtf((1.0f - progress) * (maxTapeRadius * maxTapeRadius - hubRadius * hubRadius) + hubRadius * hubRadius);
    float rightTapeR = sqrtf(progress * (maxTapeRadius * maxTapeRadius - hubRadius * hubRadius) + hubRadius * hubRadius);

    // Left Tape Pack (Oxide brown)
    [[NSColor colorWithDeviceRed:0.24f green:0.15f blue:0.10f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(leftHubX - leftTapeR, hubY - leftTapeR, leftTapeR * 2.0f, leftTapeR * 2.0f)] fill];

    // Right Tape Pack
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(rightHubX - rightTapeR, hubY - rightTapeR, rightTapeR * 2.0f, rightTapeR * 2.0f)] fill];

    // Tape ribbon running between spools
    [[NSColor colorWithDeviceRed:0.28f green:0.18f blue:0.12f alpha:1.0f] setStroke];
    NSBezierPath *tapeRibbon = [NSBezierPath bezierPath];
    [tapeRibbon setLineWidth:2.5f];
    [tapeRibbon moveToPoint:NSMakePoint(leftHubX, hubY + leftTapeR - 1.0f)];
    [tapeRibbon lineToPoint:NSMakePoint(rightHubX, hubY + rightTapeR - 1.0f)];
    [tapeRibbon stroke];

    // 5. White 6-toothed Hubs
    void (^drawReelHub)(CGFloat cx, CGFloat cy, float angle) = ^(CGFloat cx, CGFloat cy, float angle) {
        // Outer white ring
        NSRect hubR = NSMakeRect(cx - hubRadius, cy - hubRadius, hubRadius * 2.0f, hubRadius * 2.0f);
        [[NSColor colorWithDeviceRed:0.92f green:0.92f blue:0.94f alpha:1.0f] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:hubR] fill];

        // Center black hole
        CGFloat holeR = hubRadius * 0.45f;
        [[NSColor colorWithDeviceRed:0.08f green:0.08f blue:0.09f alpha:1.0f] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - holeR, cy - holeR, holeR * 2.0f, holeR * 2.0f)] fill];

        // 6 drive teeth radiating outward
        [[NSColor colorWithDeviceRed:0.22f green:0.22f blue:0.24f alpha:1.0f] setFill];
        for (int tooth = 0; tooth < 6; tooth++) {
            float toothAngle = angle + (float)tooth * (float)M_PI / 3.0f;
            CGFloat tx = cx + cosf(toothAngle) * (hubRadius * 0.65f);
            CGFloat ty = cy + sinf(toothAngle) * (hubRadius * 0.65f);
            NSRect toothRect = NSMakeRect(tx - 2.0f, ty - 2.0f, 4.0f, 4.0f);
            [[NSBezierPath bezierPathWithOvalInRect:toothRect] fill];
        }
    };

    drawReelHub(leftHubX, hubY, _reelAngle);
    drawReelHub(rightHubX, hubY, _reelAngle);

    // 6. Mechanical Tape Counter Box (above window)
    CGFloat counterW = 38.0f;
    CGFloat counterH = 14.0f;
    CGFloat counterX = windowX + (windowW - counterW) * 0.5f;
    CGFloat counterY = windowY - 12.0f;
    NSRect counterRect = NSMakeRect(counterX, counterY, counterW, counterH);
    [[NSColor blackColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:counterRect xRadius:2.0f yRadius:2.0f] fill];

    int counterValue = ((int)_playTime) % 1000;
    NSString *counterStr = [NSString stringWithFormat:@"%03d", counterValue];
    NSDictionary *counterAttr = @{
        NSFontAttributeName: [NSFont fontWithName:@"Courier-Bold" size:10.0f] ?: [NSFont boldSystemFontOfSize:9.0f],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    [counterStr drawAtPoint:NSMakePoint(counterX + 6.0f, counterY + 0.5f) withAttributes:counterAttr];

    // 7. Audio-reactive PLAY LED
    CGFloat ledX = originX + cassetteW - 20.0f;
    CGFloat ledY = originY + 12.0f;
    float ledAlpha = _isPlaying ? (0.35f + _audioLevel * 0.65f) : 0.20f;
    NSRect ledRect = NSMakeRect(ledX - 4.0f, ledY - 4.0f, 8.0f, 8.0f);
    [[NSColor colorWithDeviceRed:0.95f green:0.20f blue:0.20f alpha:ledAlpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];

    // LED glow when active
    if (_isPlaying && _audioLevel > 0.10f) {
        NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
        [ctx saveGraphicsState];
        NSShadow *glow = [[NSShadow alloc] init];
        glow.shadowColor = [NSColor colorWithDeviceRed:1.0f green:0.2f blue:0.2f alpha:_audioLevel];
        glow.shadowBlurRadius = 6.0f;
        glow.shadowOffset = NSMakeSize(0, 0);
        [glow set];
        [[NSColor colorWithDeviceRed:1.0f green:0.25f blue:0.25f alpha:1.0f] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];
        [ctx restoreGraphicsState];
    }

    // Hardware silicon chip badge on cassette shell
    NSRect chipRect = NSMakeRect(originX + cassetteW - 105.0f, originY + cassetteH - 24.0f, 88.0f, 18.0f);
    [self drawSiliconChipBadgeInRect:chipRect model:(_chipModel ?: @"MOS 6581") isMod:NO];
}

// ============================================================================
#pragma mark - Commodore 1541 Floppy Drive Rendering
// ============================================================================

- (void)drawFloppyInRect:(NSRect)bounds
{
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;

    // Dark background
    [[NSColor colorWithDeviceRed:0.10f green:0.10f blue:0.12f alpha:1.0f] setFill];
    NSRectFill(bounds);

    CGFloat driveW = MIN(width * 0.90f, height * 1.50f);
    if (driveW < 180.0f) driveW = 180.0f;
    CGFloat driveH = driveW / 1.50f;
    CGFloat originX = (width - driveW) * 0.5f;
    CGFloat originY = (height - driveH) * 0.5f;
    NSRect driveRect = NSMakeRect(originX, originY, driveW, driveH);

    // 1. Commodore 1541 Warm Beige Housing
    NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect:driveRect xRadius:8.0f yRadius:8.0f];
    [[NSColor colorWithDeviceRed:0.86f green:0.82f blue:0.75f alpha:1.0f] setFill];
    [bezel fill];
    [[NSColor colorWithDeviceRed:0.70f green:0.66f blue:0.58f alpha:1.0f] setStroke];
    [bezel setLineWidth:1.5f];
    [bezel stroke];

    // 2. Drive Horizontal Opening Slot
    CGFloat slotW = driveW * 0.88f;
    CGFloat slotH = driveH * 0.68f;
    CGFloat slotX = originX + (driveW - slotW) * 0.5f;
    CGFloat slotY = originY + driveH * 0.16f;
    NSRect slotRect = NSMakeRect(slotX, slotY, slotW, slotH);
    [[NSColor colorWithDeviceRed:0.10f green:0.10f blue:0.11f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:slotRect xRadius:4.0f yRadius:4.0f] fill];

    // 3. 5.25" Black Floppy Disk Inside Slot
    CGFloat diskW = slotW * 0.94f;
    CGFloat diskH = slotH * 0.92f;
    CGFloat diskX = slotX + (slotW - diskW) * 0.5f;
    CGFloat diskY = slotY + (slotH - diskH) * 0.5f;
    NSRect diskRect = NSMakeRect(diskX, diskY, diskW, diskH);
    NSBezierPath *diskPath = [NSBezierPath bezierPathWithRoundedRect:diskRect xRadius:4.0f yRadius:4.0f];
    [[NSColor colorWithDeviceRed:0.16f green:0.16f blue:0.18f alpha:1.0f] setFill];
    [diskPath fill];

    // Floppy White Label at top of disk
    CGFloat diskLabelH = diskH * 0.28f;
    NSRect diskLabelRect = NSMakeRect(diskX + 8.0f, diskY + 6.0f, diskW - 16.0f, diskLabelH);
    [[NSColor colorWithDeviceRed:0.94f green:0.94f blue:0.92f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:diskLabelRect xRadius:3.0f yRadius:3.0f] fill];

    // Label Text
    NSDictionary *c1541Attr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:MIN(10.0f, diskW * 0.045f)],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.15f green:0.30f blue:0.60f alpha:1.0f]
    };
    [@"C= COMMODORE 1541 DISK" drawAtPoint:NSMakePoint(diskX + 14.0f, diskY + 9.0f) withAttributes:c1541Attr];

    NSString *trackTitle = (_tuneTitle && [_tuneTitle length] > 0) ? _tuneTitle : @"SID MUSIC DISK";
    NSDictionary *trackAttr = @{
        NSFontAttributeName: [NSFont fontWithName:@"Courier-Bold" size:MIN(10.0f, diskW * 0.042f)] ?: [NSFont boldSystemFontOfSize:9.0f],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.20f green:0.20f blue:0.22f alpha:1.0f]
    };
    NSRect trackRect = NSMakeRect(diskX + 14.0f, diskY + 22.0f, diskW - 28.0f, 14.0f);
    [trackTitle drawInRect:trackRect withAttributes:trackAttr];

    // Write protect notch cutout on left
    [[NSColor colorWithDeviceRed:0.10f green:0.10f blue:0.11f alpha:1.0f] setFill];
    NSRectFill(NSMakeRect(diskX, diskY + diskH * 0.40f, 6.0f, 10.0f));

    // 4. Center Spindle Cutout & Spinning Magnetic Disk
    CGFloat spindleCx = diskX + diskW * 0.50f;
    CGFloat spindleCy = diskY + diskH * 0.62f;
    CGFloat spindleR = diskH * 0.22f;

    // Dark oxide magnetic disk surface inside cutout
    NSRect spindleOuterR = NSMakeRect(spindleCx - spindleR, spindleCy - spindleR, spindleR * 2.0f, spindleR * 2.0f);
    [[NSColor colorWithDeviceRed:0.18f green:0.13f blue:0.09f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:spindleOuterR] fill];

    // White hub reinforcement ring
    CGFloat ringR = spindleR * 0.72f;
    [[NSColor colorWithDeviceRed:0.92f green:0.92f blue:0.90f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(spindleCx - ringR, spindleCy - ringR, ringR * 2.0f, ringR * 2.0f)] fill];

    // Inner Drive Spindle Clamp (metallic)
    CGFloat innerHoleR = ringR * 0.55f;
    [[NSColor colorWithDeviceRed:0.25f green:0.26f blue:0.28f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(spindleCx - innerHoleR, spindleCy - innerHoleR, innerHoleR * 2.0f, innerHoleR * 2.0f)] fill];

    // 3 rotating clamp notches
    [[NSColor colorWithDeviceRed:0.55f green:0.56f blue:0.60f alpha:1.0f] setFill];
    for (int k = 0; k < 3; k++) {
        float angle = _floppyAngle + (float)k * (2.0f * (float)M_PI / 3.0f);
        CGFloat nx = spindleCx + cosf(angle) * (innerHoleR * 0.60f);
        CGFloat ny = spindleCy + sinf(angle) * (innerHoleR * 0.60f);
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(nx - 2.5f, ny - 2.5f, 5.0f, 5.0f)] fill];
    }

    // 5. Classic Commodore LEDs (POWER & DRIVE)
    CGFloat ledGreenX = originX + driveW - 46.0f;
    CGFloat ledRedX = originX + driveW - 20.0f;
    CGFloat ledY = originY + 12.0f;

    // Green POWER LED (Steady green)
    NSRect greenRect = NSMakeRect(ledGreenX - 4.0f, ledY - 4.0f, 8.0f, 8.0f);
    [[NSColor colorWithDeviceRed:0.15f green:0.80f blue:0.25f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:greenRect] fill];

    // Red DRIVE ACTIVITY LED (Flickers on playback activity)
    float redAlpha = (_isPlaying && _driveFlicker > 0.20f) ? 1.0f : 0.25f;
    NSRect redRect = NSMakeRect(ledRedX - 4.0f, ledY - 4.0f, 8.0f, 8.0f);
    [[NSColor colorWithDeviceRed:0.95f green:0.20f blue:0.20f alpha:redAlpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:redRect] fill];

    if (_isPlaying && _driveFlicker > 0.20f) {
        NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
        [ctx saveGraphicsState];
        NSShadow *glow = [[NSShadow alloc] init];
        glow.shadowColor = [NSColor colorWithDeviceRed:1.0f green:0.2f blue:0.2f alpha:_driveFlicker];
        glow.shadowBlurRadius = 8.0f;
        glow.shadowOffset = NSMakeSize(0, 0);
        [glow set];
        [[NSColor colorWithDeviceRed:1.0f green:0.25f blue:0.25f alpha:1.0f] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:redRect] fill];
        [ctx restoreGraphicsState];
    }

    // LED Labels
    NSDictionary *ledLabelAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:7.5f],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.35f green:0.35f blue:0.38f alpha:1.0f]
    };
    [@"PWR" drawAtPoint:NSMakePoint(ledGreenX - 7.0f, ledY + 5.0f) withAttributes:ledLabelAttr];
    [@"ACT" drawAtPoint:NSMakePoint(ledRedX - 7.0f, ledY + 5.0f) withAttributes:ledLabelAttr];

    // Commodore 1541 Brand Badge
    NSDictionary *brandAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9.0f],
        NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.30f green:0.30f blue:0.35f alpha:1.0f]
    };
    [@"C= commodore 1541" drawAtPoint:NSMakePoint(originX + 14.0f, originY + 6.0f) withAttributes:brandAttr];

    // Hardware silicon chip badge on 1541 bezel
    NSRect chipRect = NSMakeRect(originX + 130.0f, originY + 5.0f, 86.0f, 16.0f);
    [self drawSiliconChipBadgeInRect:chipRect model:(_chipModel ?: @"MOS 6581") isMod:NO];
}

// ============================================================================
#pragma mark - Classic Spectrum Bars Rendering
// ============================================================================

- (void)drawSpectrumInRect:(NSRect)bounds
{
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(bounds);

    // Hardware silicon chip badge in upper right corner
    NSRect chipRect = NSMakeRect(bounds.size.width - 96.0f, 6.0f, 88.0f, 18.0f);
    [self drawSiliconChipBadgeInRect:chipRect model:(_chipModel ?: (_isMod ? @"PAULA 8364" : @"MOS 6581")) isMod:_isMod];

    CGFloat gap = 2.0f;
    CGFloat totalGap = gap * (kSpectrumBarCount + 1);
    CGFloat barWidth = (bounds.size.width - totalGap) / (CGFloat)kSpectrumBarCount;
    if (barWidth < 1.0f) {
        barWidth = 1.0f;
    }

    CGFloat maxHeight = bounds.size.height - 4.0f;
    CGFloat originY = 2.0f;
    CGFloat inset = 3.0f;

    CGFloat trackRadius = MIN(barWidth, maxHeight) * 0.2f;
    if (trackRadius < 2.0f) {
        trackRadius = 2.0f;
    }
    for (int i = 0; i < kSpectrumBarCount; i++) {
        CGFloat level = _barLevels[i];
        CGFloat innerHeight = maxHeight - inset * 2.0f;
        if (innerHeight < 1.0f) {
            innerHeight = 1.0f;
        }
        CGFloat barHeight = innerHeight * level;
        CGFloat x = gap + (barWidth + gap) * (CGFloat)i;
        NSRect backRect = NSMakeRect(x, originY, barWidth, maxHeight);
        [[NSColor blackColor] setFill];
        NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect:backRect
                                                                  xRadius:trackRadius
                                                                  yRadius:trackRadius];
        [trackPath fill];

        CGFloat innerWidth = barWidth - inset * 2.0f;
        if (innerWidth < 1.0f) {
            innerWidth = 1.0f;
        }
        CGFloat innerY = originY + inset;
        CGFloat barTop = innerY + (innerHeight - barHeight);
        CGFloat barBottom = innerY + innerHeight;
        NSRect barRect = NSMakeRect(x + inset,
                                    barTop,
                                    innerWidth,
                                    barHeight);
        float t = kSpectrumBarCount > 1 ? (float)i / (float)(kSpectrumBarCount - 1) : 0.0f;
        NSColor *barColor = [NSColor colorWithDeviceRed:(1.0f - t) green:0.0f blue:t alpha:1.0f];
        NSColor *glowColor = [NSColor colorWithDeviceRed:(1.0f - t) green:0.0f blue:t alpha:0.55f];
        CGFloat segmentHeight = 10.0f;
        CGFloat segmentGap = 3.0f;
        CGFloat segmentStride = segmentHeight + segmentGap;
        CGFloat segmentRadius = MIN(innerWidth, segmentHeight) * 0.25f;
        if (segmentRadius < 1.0f) {
            segmentRadius = 1.0f;
        }

        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        [context saveGraphicsState];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = glowColor;
        shadow.shadowBlurRadius = 6.0f;
        shadow.shadowOffset = NSMakeSize(0.0f, 0.0f);
        [shadow set];
        [barColor setFill];

        for (CGFloat y = barBottom - segmentHeight; y >= barTop; y -= segmentStride) {
            CGFloat visibleHeight = segmentHeight;
            if (y < barTop) {
                visibleHeight = segmentHeight - (barTop - y);
                y = barTop;
            }
            if (visibleHeight <= 0.0f) {
                break;
            }
            NSRect segmentRect = NSMakeRect(barRect.origin.x, y, barRect.size.width, visibleHeight);
            NSBezierPath *segmentPath = [NSBezierPath bezierPathWithRoundedRect:segmentRect
                                                                        xRadius:segmentRadius
                                                                        yRadius:segmentRadius];
            [segmentPath fill];
        }
        [context restoreGraphicsState];

        [barColor setFill];
        for (CGFloat y = barBottom - segmentHeight; y >= barTop; y -= segmentStride) {
            CGFloat visibleHeight = segmentHeight;
            if (y < barTop) {
                visibleHeight = segmentHeight - (barTop - y);
                y = barTop;
            }
            if (visibleHeight <= 0.0f) {
                break;
            }
            NSRect segmentRect = NSMakeRect(barRect.origin.x, y, barRect.size.width, visibleHeight);
            NSBezierPath *segmentPath = [NSBezierPath bezierPathWithRoundedRect:segmentRect
                                                                        xRadius:segmentRadius
                                                                        yRadius:segmentRadius];
            [segmentPath fill];
        }
    }
}

// ============================================================================
#pragma mark - CRT Monitor & Scanlines Overlay
// ============================================================================

- (void)drawCRTOverlayInRect:(NSRect)bounds
{
    if (!_crtEffectEnabled) return;

    // 1. Color Phosphor Tinting (for Amber, Green, or C64 Cyan)
    if (_crtProfile == SPCRTDisplayProfileAmber) {
        [[NSColor colorWithDeviceRed:1.0f green:0.65f blue:0.10f alpha:0.18f] setFill];
        NSRectFillUsingOperation(bounds, NSCompositingOperationColor);
    } else if (_crtProfile == SPCRTDisplayProfileGreen) {
        [[NSColor colorWithDeviceRed:0.20f green:1.0f blue:0.35f alpha:0.18f] setFill];
        NSRectFillUsingOperation(bounds, NSCompositingOperationColor);
    } else if (_crtProfile == SPCRTDisplayProfileC64Cyan) {
        [[NSColor colorWithDeviceRed:0.25f green:0.55f blue:0.95f alpha:0.18f] setFill];
        NSRectFillUsingOperation(bounds, NSCompositingOperationColor);
    }

    // 2. Horizontal Raster Scanlines
    NSBezierPath *scanlines = [NSBezierPath bezierPath];
    [scanlines setLineWidth:1.0f];
    for (CGFloat y = 0.0f; y < bounds.size.height; y += 2.0f) {
        [scanlines moveToPoint:NSMakePoint(0.0f, y)];
        [scanlines lineToPoint:NSMakePoint(bounds.size.width, y)];
    }
    [[NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.16f] setStroke];
    [scanlines stroke];

    // 3. Subtle RGB Shadow Mask / Aperture Grille (in 1084S mode)
    if (_crtProfile == SPCRTDisplayProfile1084SColor) {
        NSBezierPath *rgbLines = [NSBezierPath bezierPath];
        [rgbLines setLineWidth:0.5f];
        for (CGFloat x = 0.0f; x < bounds.size.width; x += 3.0f) {
            [rgbLines moveToPoint:NSMakePoint(x, 0.0f)];
            [rgbLines lineToPoint:NSMakePoint(x, bounds.size.height)];
        }
        [[NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.08f] setStroke];
        [rgbLines stroke];
    }

    // 4. CRT Glass Curvature Vignette (Darkened edges & corners)
    NSGradient *vignetteTop = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.35f],
        [NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.0f]
    ]];
    CGFloat shadowInset = 12.0f;
    [vignetteTop drawInRect:NSMakeRect(0, 0, bounds.size.width, shadowInset) angle:90.0f];
    [vignetteTop drawInRect:NSMakeRect(0, bounds.size.height - shadowInset, bounds.size.width, shadowInset) angle:-90.0f];
    [vignetteTop drawInRect:NSMakeRect(0, 0, shadowInset, bounds.size.height) angle:0.0f];
    [vignetteTop drawInRect:NSMakeRect(bounds.size.width - shadowInset, 0, shadowInset, bounds.size.height) angle:180.0f];

    // 5. Curved Glass Reflection Glint (diagonal highlight across corner)
    NSBezierPath *glassGlint = [NSBezierPath bezierPath];
    [glassGlint moveToPoint:NSMakePoint(6.0f, 6.0f)];
    [glassGlint lineToPoint:NSMakePoint(bounds.size.width * 0.42f, 6.0f)];
    [glassGlint lineToPoint:NSMakePoint(6.0f, bounds.size.height * 0.42f)];
    [glassGlint closePath];
    [[NSColor colorWithDeviceRed:1.0f green:1.0f blue:1.0f alpha:0.035f] setFill];
    [glassGlint fill];

    // 6. Monitor Bezel Border
    NSBezierPath *bezelBorder = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6.0f yRadius:6.0f];
    [[NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.60f] setStroke];
    [bezelBorder setLineWidth:2.0f];
    [bezelBorder stroke];
}

// ============================================================================
#pragma mark - HUD Mode Overlay
// ============================================================================

- (void)drawHudOverlayInRect:(NSRect)bounds
{
    NSDictionary *hudAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0f],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [_hudText sizeWithAttributes:hudAttr];
    CGFloat padX = 14.0f;
    CGFloat padY = 6.0f;
    CGFloat pillW = textSize.width + padX * 2.0f;
    CGFloat pillH = textSize.height + padY * 2.0f;
    CGFloat pillX = (bounds.size.width - pillW) * 0.5f;
    CGFloat pillY = bounds.size.height - pillH - 12.0f;

    NSRect pillRect = NSMakeRect(pillX, pillY, pillW, pillH);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:pillH * 0.5f yRadius:pillH * 0.5f];
    [[NSColor colorWithDeviceRed:0.05f green:0.05f blue:0.08f alpha:0.82f] setFill];
    [pill fill];
    [[NSColor colorWithDeviceRed:0.50f green:0.50f blue:0.60f alpha:0.40f] setStroke];
    [pill setLineWidth:1.0f];
    [pill stroke];

    [_hudText drawAtPoint:NSMakePoint(pillX + padX, pillY + padY) withAttributes:hudAttr];
}

@end
