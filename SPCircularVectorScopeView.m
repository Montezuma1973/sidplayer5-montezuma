//
//  SPCircularVectorScopeView.m
//  SIDPLAY
//
//  Circular Radar Phosphor Vector Oscilloscope with Lissajous,
//  Circular Waveform, and Radar Sweep modes.
//

#import "SPCircularVectorScopeView.h"
#import "SPPlayerWindow.h"
#import "SPThemeManager.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface SPCircularVectorScopeView ()
{
    NSTimer *_refreshTimer;
    CGFloat _sweepAngle;       // in radians
    CGFloat _phaseOffset;
    short _cachedSamples[1024];
    NSUInteger _sampleCount;
}
@end

@implementation SPCircularVectorScopeView

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
    _scopeMode = SPVectorScopeModeLissajousXY;
    _phosphorColor = [NSColor colorWithCalibratedRed:0.18f green:0.95f blue:0.42f alpha:1.0f]; // classic P31 green phosphor
    _sweepAngle = 0.0f;
    _phaseOffset = 0.0f;
    _sampleCount = 0;
    _isRunning = NO;
    
    [self setWantsLayer:YES];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window) {
        [self startScope];
    } else {
        [self stopScope];
    }
}

- (void)startScope
{
    if (_isRunning) return;
    _isRunning = YES;
    
    __weak typeof(self) weakSelf = self;
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0) repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf timerFired];
    }];
}

- (void)stopScope
{
    _isRunning = NO;
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)cycleScopeMode
{
    self.scopeMode = (self.scopeMode + 1) % 3;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    [self cycleScopeMode];
}

- (void)timerFired
{
    _sweepAngle += 0.08f;
    if (_sweepAngle > M_PI * 2.0f) {
        _sweepAngle -= M_PI * 2.0f;
    }
    _phaseOffset += 0.05f;
    
    if (_playerWindow && [_playerWindow audioDriverIsPlaying]) {
        short *buf = [_playerWindow audioDriverSampleBuffer];
        if (buf != NULL) {
            _sampleCount = 512;
            memcpy(_cachedSamples, buf, _sampleCount * sizeof(short));
        } else {
            _sampleCount = 0;
        }
    } else {
        _sampleCount = 0;
    }
    
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if (!ctx) return;
    
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    CGFloat minDim = MIN(w, h);
    CGPoint center = CGPointMake(bounds.origin.x + w * 0.5f, bounds.origin.y + h * 0.5f);
    CGFloat outerRadius = (minDim * 0.5f) - 6.0f;
    if (outerRadius < 20.0f) return;
    
    // 1. Metal Bezel Ring (Outer clamp ring)
    NSRect bezelRect = NSMakeRect(center.x - outerRadius, center.y - outerRadius, outerRadius * 2.0f, outerRadius * 2.0f);
    
    NSColor *bezelTop = [NSColor colorWithCalibratedRed:0.25f green:0.28f blue:0.32f alpha:1.0f];
    NSColor *bezelBot = [NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:1.0f];
    NSGradient *bezelGrad = [[NSGradient alloc] initWithStartingColor:bezelTop endingColor:bezelBot];
    [bezelGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:bezelRect] angle:-45.0f];
    
    // Outer shadow ring
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.8f] setStroke];
    NSBezierPath *bezelBorder = [NSBezierPath bezierPathWithOvalInRect:bezelRect];
    bezelBorder.lineWidth = 2.0f;
    [bezelBorder stroke];
    
    // 2. Degree Graduation Ticks on Bezel
    CGFloat tickRadius = outerRadius - 3.0f;
    for (int deg = 0; deg < 360; deg += 30) {
        CGFloat rad = deg * M_PI / 180.0f;
        CGFloat x1 = center.x + (tickRadius - ((deg % 90 == 0) ? 5.0f : 3.0f)) * cos(rad);
        CGFloat y1 = center.y + (tickRadius - ((deg % 90 == 0) ? 5.0f : 3.0f)) * sin(rad);
        CGFloat x2 = center.x + tickRadius * cos(rad);
        CGFloat y2 = center.y + tickRadius * sin(rad);
        
        NSBezierPath *tickPath = [NSBezierPath bezierPath];
        [tickPath moveToPoint:NSMakePoint(x1, y1)];
        [tickPath lineToPoint:NSMakePoint(x2, y2)];
        tickPath.lineWidth = (deg % 90 == 0) ? 1.5f : 0.8f;
        [[NSColor colorWithCalibratedWhite:0.75f alpha:0.7f] setStroke];
        [tickPath stroke];
    }
    
    // 3. CRT Screen Cavity (Glass Bulb)
    CGFloat crtRadius = outerRadius - 10.0f;
    NSRect crtRect = NSMakeRect(center.x - crtRadius, center.y - crtRadius, crtRadius * 2.0f, crtRadius * 2.0f);
    
    // Dark deep phosphor tube background (with dark green/amber undertone)
    NSColor *screenCenter = [NSColor colorWithCalibratedRed:0.02f green:0.06f blue:0.04f alpha:1.0f];
    NSColor *screenEdge = [NSColor colorWithCalibratedRed:0.01f green:0.02f blue:0.02f alpha:1.0f];
    NSGradient *screenGrad = [[NSGradient alloc] initWithStartingColor:screenCenter endingColor:screenEdge];
    [screenGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:crtRect] angle:90.0f];
    
    // Recessed inner shadow on glass rim
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.95f] setStroke];
    NSBezierPath *crtBorder = [NSBezierPath bezierPathWithOvalInRect:crtRect];
    crtBorder.lineWidth = 2.0f;
    [crtBorder stroke];
    
    // Clip drawing to CRT circular tube
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, crtRect);
    CGContextClip(ctx);
    
    // 4. Graticule Rings & Crosshairs
    NSColor *gratColor = [NSColor colorWithCalibratedRed:0.10f green:0.35f blue:0.18f alpha:0.5f];
    if ([self.phosphorColor redComponent] > [self.phosphorColor greenComponent]) {
        // Amber graticule if amber phosphor
        gratColor = [NSColor colorWithCalibratedRed:0.35f green:0.22f blue:0.08f alpha:0.5f];
    }
    [gratColor setStroke];
    
    // Concentric range circles (25%, 50%, 75%, 100%)
    for (int i = 1; i <= 4; i++) {
        CGFloat r = crtRadius * (i * 0.25f);
        NSRect rRect = NSMakeRect(center.x - r, center.y - r, r * 2.0f, r * 2.0f);
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:rRect];
        ring.lineWidth = (i == 4) ? 1.0f : 0.6f;
        if (i < 4) {
            CGFloat dashes[] = { 2.0f, 3.0f };
            [ring setLineDash:dashes count:2 phase:0.0f];
        }
        [ring stroke];
    }
    
    // Crosshair axes (X and Y)
    NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross moveToPoint:NSMakePoint(center.x - crtRadius, center.y)];
    [cross lineToPoint:NSMakePoint(center.x + crtRadius, center.y)];
    [cross moveToPoint:NSMakePoint(center.x, center.y - crtRadius)];
    [cross lineToPoint:NSMakePoint(center.x, center.y + crtRadius)];
    cross.lineWidth = 0.8f;
    CGFloat axisDashes[] = { 1.0f, 3.0f };
    [cross setLineDash:axisDashes count:2 phase:0.0f];
    [cross stroke];
    
    // 5. Active Vector Scope Beam / Trace Rendering
    NSColor *beamCore = self.phosphorColor ?: [NSColor greenColor];
    NSColor *beamGlow = [beamCore colorWithAlphaComponent:0.35f];
    
    CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0f, beamCore.CGColor);
    
    BOOL isPlaying = (_playerWindow != nil) && [_playerWindow audioDriverIsPlaying];
    
    switch (_scopeMode) {
        case SPVectorScopeModeLissajousXY: {
            // Stereo Phase Lissajous (X = Left, Y = Right)
            NSBezierPath *trace = [NSBezierPath bezierPath];
            NSUInteger points = (_sampleCount > 0) ? (_sampleCount / 2) : 256;
            
            CGFloat scale = crtRadius * 0.75f;
            BOOL started = NO;
            
            for (NSUInteger i = 0; i < points; i++) {
                CGFloat xVal = 0.0f;
                CGFloat yVal = 0.0f;
                
                if (isPlaying && _sampleCount > 0 && (i * 2 + 1) < _sampleCount) {
                    short lSamp = _cachedSamples[i * 2];
                    short rSamp = _cachedSamples[i * 2 + 1];
                    xVal = (CGFloat)lSamp / 32768.0f;
                    yVal = (CGFloat)rSamp / 32768.0f;
                    
                    // Add slight stereo cross-rotation for organic Lissajous look
                    CGFloat rx = (xVal - yVal) * 0.7071f;
                    CGFloat ry = (xVal + yVal) * 0.7071f;
                    xVal = rx;
                    yVal = ry;
                } else {
                    // Idling Lissajous Lissajous loop (figure-8 / ellipse harmonics)
                    CGFloat t = (CGFloat)i / (CGFloat)points * M_PI * 2.0f;
                    xVal = sin(t * 2.0f + _phaseOffset) * 0.35f;
                    yVal = cos(t * 3.0f + _phaseOffset * 0.7f) * 0.35f;
                }
                
                CGFloat px = center.x + xVal * scale;
                CGFloat py = center.y + yVal * scale;
                
                if (!started) {
                    [trace moveToPoint:NSMakePoint(px, py)];
                    started = YES;
                } else {
                    [trace lineToPoint:NSMakePoint(px, py)];
                }
            }
            
            // Draw glow halo
            [beamGlow setStroke];
            trace.lineWidth = 3.0f;
            [trace stroke];
            
            // Draw sharp beam core
            [beamCore setStroke];
            trace.lineWidth = 1.2f;
            [trace stroke];
            break;
        }
            
        case SPVectorScopeModeCircularWave: {
            // 360-degree Radial Waveform
            NSBezierPath *wave = [NSBezierPath bezierPath];
            NSUInteger points = 360;
            CGFloat baseR = crtRadius * 0.55f;
            
            BOOL started = NO;
            for (NSUInteger deg = 0; deg <= points; deg++) {
                CGFloat rad = deg * M_PI / 180.0f;
                CGFloat amp = 0.0f;
                
                if (isPlaying && _sampleCount > 0) {
                    NSUInteger idx = (deg * _sampleCount) / points;
                    if (idx < _sampleCount) {
                        amp = ((CGFloat)_cachedSamples[idx] / 32768.0f) * (crtRadius * 0.35f);
                    }
                } else {
                    // Pulsing idle harmonic ripples
                    amp = sin(rad * 6.0f + _phaseOffset * 2.0f) * 6.0f + cos(rad * 3.0f - _phaseOffset) * 4.0f;
                }
                
                CGFloat r = baseR + amp;
                if (r < 5.0f) r = 5.0f;
                if (r > crtRadius - 4.0f) r = crtRadius - 4.0f;
                
                CGFloat px = center.x + r * cos(rad);
                CGFloat py = center.y + r * sin(rad);
                
                if (!started) {
                    [wave moveToPoint:NSMakePoint(px, py)];
                    started = YES;
                } else {
                    [wave lineToPoint:NSMakePoint(px, py)];
                }
            }
            [wave closePath];
            
            [beamGlow setStroke];
            wave.lineWidth = 3.0f;
            [wave stroke];
            
            [beamCore setStroke];
            wave.lineWidth = 1.4f;
            [wave stroke];
            break;
        }
            
        case SPVectorScopeModeRadarSweep: {
            // Rotating Radar Beam with trailing persistence sector
            CGFloat sweepLen = crtRadius - 2.0f;
            
            // Trailing decay fan (wedge)
            CGFloat trailAngle = 0.65f; // radians
            NSBezierPath *fan = [NSBezierPath bezierPath];
            [fan moveToPoint:center];
            [fan appendBezierPathWithArcWithCenter:center
                                            radius:sweepLen
                                        startAngle:(_sweepAngle - trailAngle) * 180.0f / M_PI
                                          endAngle:_sweepAngle * 180.0f / M_PI
                                         clockwise:NO];
            [fan closePath];
            
            [[beamCore colorWithAlphaComponent:0.18f] setFill];
            [fan fill];
            
            // Leading Sweep Beam
            CGFloat bx = center.x + sweepLen * cos(_sweepAngle);
            CGFloat by = center.y + sweepLen * sin(_sweepAngle);
            
            NSBezierPath *beam = [NSBezierPath bezierPath];
            [beam moveToPoint:center];
            [beam lineToPoint:NSMakePoint(bx, by)];
            
            [beamGlow setStroke];
            beam.lineWidth = 3.0f;
            [beam stroke];
            
            [beamCore setStroke];
            beam.lineWidth = 1.5f;
            [beam stroke];
            
            // Audio blips along the sweep radius
            if (isPlaying && _sampleCount > 0) {
                CGFloat samp = fabs((CGFloat)_cachedSamples[0] / 32768.0f);
                CGFloat blipR = crtRadius * (0.3f + samp * 0.5f);
                CGFloat blipX = center.x + blipR * cos(_sweepAngle);
                CGFloat blipY = center.y + blipR * sin(_sweepAngle);
                
                NSRect blipRect = NSMakeRect(blipX - 3.0f, blipY - 3.0f, 6.0f, 6.0f);
                [[NSColor whiteColor] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:blipRect] fill];
            }
            break;
        }
    }
    
    // 6. Glass Reflection Highlight (Arc on top of bulb)
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    NSRect highlightRect = NSMakeRect(center.x - crtRadius * 0.75f, center.y + crtRadius * 0.15f, crtRadius * 1.5f, crtRadius * 0.65f);
    NSBezierPath *highlight = [NSBezierPath bezierPathWithOvalInRect:highlightRect];
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.07f] setFill];
    [highlight fill];
    
    CGContextRestoreGState(ctx);
    
    // 7. Mode Label Badge (at bottom edge of scope)
    NSString *modeLabel = @"LISSAJOUS X-Y";
    if (_scopeMode == SPVectorScopeModeCircularWave) modeLabel = @"RADIAL WAVE";
    else if (_scopeMode == SPVectorScopeModeRadarSweep) modeLabel = @"RADAR SWEEP";
    
    NSFont *scopeFont = [NSFont monospacedSystemFontOfSize:8.0f weight:NSFontWeightBold] ?: [NSFont boldSystemFontOfSize:8.0f] ?: [NSFont systemFontOfSize:8.0f];
    NSMutableDictionary *labelAttr = [NSMutableDictionary dictionaryWithCapacity:2];
    if (scopeFont) labelAttr[NSFontAttributeName] = scopeFont;
    if (beamCore) labelAttr[NSForegroundColorAttributeName] = [beamCore colorWithAlphaComponent:0.85f];
    NSSize lSize = [modeLabel sizeWithAttributes:labelAttr];
    [modeLabel drawAtPoint:NSMakePoint(center.x - lSize.width * 0.5f, bounds.origin.y + 4.0f) withAttributes:labelAttr];
}

@end
