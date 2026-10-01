//
//  SPKnurledKnobControl.m
//  SIDPLAY
//
//  Non-standard tactile rotary knob control with knurled aluminum dial,
//  LED indicator arc collar, and radial mouse dragging physics.
//

#import "SPKnurledKnobControl.h"

@interface SPKnurledKnobControl () {
    NSPoint _lastDragPoint;
    BOOL _isDragging;
}
@end

@implementation SPKnurledKnobControl

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect
                         title:@"KNOB"
                          unit:@"%"
                      minValue:0.0f
                      maxValue:100.0f
                  initialValue:50.0f
                         color:SPKnobColorCyan];
}

- (instancetype)initWithFrame:(NSRect)frameRect
                        title:(NSString *)title
                         unit:(NSString *)unit
                     minValue:(float)minVal
                     maxValue:(float)maxVal
                 initialValue:(float)initVal
                        color:(SPKnobColor)color
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _titleText = [title copy];
        _unitText = [unit copy];
        _minValue = minVal;
        _maxValue = maxVal;
        _knobValue = initVal;
        _ledColor = color;
        _showArcMeter = YES;
    }
    return self;
}

- (void)setKnobValue:(float)knobValue {
    float clamped = MAX(_minValue, MIN(_maxValue, knobValue));
    if (_knobValue != clamped) {
        _knobValue = clamped;
        [self setNeedsDisplay:YES];
    }
}

- (float)floatValue {
    return _knobValue;
}

- (void)setFloatValue:(float)val {
    self.knobValue = val;
}

- (NSColor *)neonColor {
    switch (_ledColor) {
        case SPKnobColorCyan:
            return [NSColor colorWithCalibratedRed:0.0f green:0.94f blue:1.0f alpha:1.0f];
        case SPKnobColorAmber:
            return [NSColor colorWithCalibratedRed:1.0f green:0.65f blue:0.10f alpha:1.0f];
        case SPKnobColorEmerald:
            return [NSColor colorWithCalibratedRed:0.22f green:1.0f blue:0.35f alpha:1.0f];
        case SPKnobColorPurple:
            return [NSColor colorWithCalibratedRed:0.75f green:0.35f blue:1.0f alpha:1.0f];
    }
}

#pragma mark - Mouse Tracking

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    _lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.isEnabled || !_isDragging) return;
    NSPoint curPoint = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat deltaY = curPoint.y - _lastDragPoint.y;
    CGFloat deltaX = curPoint.x - _lastDragPoint.x;
    _lastDragPoint = curPoint;

    // Linear upward/rightward drag increases value
    CGFloat delta = (deltaY + deltaX * 0.5f);
    float range = _maxValue - _minValue;
    float step = (range / 150.0f) * (float)delta;
    
    self.knobValue = self.knobValue + step;
    [self sendAction:self.action to:self.target];
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.isEnabled) return;
    float range = _maxValue - _minValue;
    float delta = (float)(event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY);
    float step = (range / 80.0f) * delta;
    self.knobValue = self.knobValue + step;
    [self sendAction:self.action to:self.target];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    NSRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    // Geometry
    CGFloat labelAreaHeight = 32.0f;
    CGFloat knobAreaHeight = h - labelAreaHeight;
    CGFloat knobSize = MIN(w - 12.0f, knobAreaHeight - 8.0f);
    if (knobSize < 20.0f) knobSize = 20.0f;
    
    NSPoint center = NSMakePoint(w * 0.5f, h - (knobSize * 0.5f) - 6.0f);
    CGFloat radius = knobSize * 0.5f;
    
    // Normalized 0.0 .. 1.0
    float norm = (_maxValue > _minValue) ? (_knobValue - _minValue) / (_maxValue - _minValue) : 0.0f;
    norm = MAX(0.0f, MIN(1.0f, norm));

    // Sweep: Start from 225 deg (bottom-left) to -45 deg (bottom-right), total 270 deg
    CGFloat startAngle = 225.0f;
    CGFloat totalSweep = 270.0f;
    CGFloat currentAngle = startAngle - (norm * totalSweep);
    
    // 1. Draw Outer LED Arc Collar
    if (_showArcMeter) {
        CGFloat arcRadius = radius + 3.5f;
        
        // Background track arc
        NSBezierPath *bgArc = [NSBezierPath bezierPath];
        [bgArc appendBezierPathWithArcWithCenter:center radius:arcRadius startAngle:startAngle endAngle:-45.0f clockwise:YES];
        [[NSColor colorWithCalibratedRed:0.12f green:0.14f blue:0.18f alpha:1.0f] setStroke];
        [bgArc setLineWidth:3.0f];
        [bgArc stroke];
        
        // Active illuminated LED arc
        if (norm > 0.005f) {
            NSBezierPath *activeArc = [NSBezierPath bezierPath];
            [activeArc appendBezierPathWithArcWithCenter:center radius:arcRadius startAngle:startAngle endAngle:currentAngle clockwise:YES];
            NSColor *neon = [self neonColor];
            
            // Soft outer glow pass
            [[neon colorWithAlphaComponent:0.35f] setStroke];
            [activeArc setLineWidth:5.0f];
            [activeArc stroke];
            
            // Core bright neon stroke
            [neon setStroke];
            [activeArc setLineWidth:2.5f];
            [activeArc stroke];
        }
    }
    
    // 2. Knob Drop Shadow
    NSRect shadowRect = NSMakeRect(center.x - radius + 1.0f, center.y - radius - 3.0f, radius * 2.0f, radius * 2.0f);
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.6f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:shadowRect] fill];
    
    // 3. Knurled Outer Ring (Grooved Gear Teeth)
    int numTeeth = 32;
    NSColor *toothLight = [NSColor colorWithCalibratedRed:0.28f green:0.30f blue:0.36f alpha:1.0f];
    NSColor *toothDark = [NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:1.0f];
    
    for (int i = 0; i < numTeeth; i++) {
        CGFloat th = (2.0f * M_PI / numTeeth) * i;
        CGFloat x1 = center.x + (radius - 1.0f) * cos(th);
        CGFloat y1 = center.y + (radius - 1.0f) * sin(th);
        CGFloat x2 = center.x + (radius - 5.0f) * cos(th);
        CGFloat y2 = center.y + (radius - 5.0f) * sin(th);
        
        NSBezierPath *groove = [NSBezierPath bezierPath];
        [groove moveToPoint:NSMakePoint(x1, y1)];
        [groove lineToPoint:NSMakePoint(x2, y2)];
        groove.lineWidth = 1.2f;
        [((i % 2 == 0) ? toothLight : toothDark) setStroke];
        [groove stroke];
    }
    
    // 4. Aluminum Dial Face (Machined Bevel Gradient)
    CGFloat innerRadius = radius - 4.5f;
    NSRect innerRect = NSMakeRect(center.x - innerRadius, center.y - innerRadius, innerRadius * 2.0f, innerRadius * 2.0f);
    
    NSColor *cTop = _isDragging ? [NSColor colorWithCalibratedRed:0.24f green:0.26f blue:0.32f alpha:1.0f] : [NSColor colorWithCalibratedRed:0.20f green:0.22f blue:0.27f alpha:1.0f];
    NSColor *cBot = _isDragging ? [NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:1.0f] : [NSColor colorWithCalibratedRed:0.09f green:0.10f blue:0.12f alpha:1.0f];
    NSGradient *dialGrad = [[NSGradient alloc] initWithStartingColor:cTop endingColor:cBot];
    [dialGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:innerRect] angle:-65.0f];
    
    // Bevel Rim
    [[NSColor colorWithCalibratedRed:0.35f green:0.38f blue:0.45f alpha:0.8f] setStroke];
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:innerRect];
    rim.lineWidth = 1.0f;
    [rim stroke];
    
    // 5. Dial Indicator Pip / Notch
    CGFloat curRad = currentAngle * M_PI / 180.0f;
    CGFloat pipRadius = innerRadius - 4.0f;
    CGFloat pipX = center.x + pipRadius * cos(curRad);
    CGFloat pipY = center.y + pipRadius * sin(curRad);
    
    // Glowing pip
    NSColor *neon = [self neonColor];
    NSRect pipRect = NSMakeRect(pipX - 2.5f, pipY - 2.5f, 5.0f, 5.0f);
    
    // Glow aura
    [[neon colorWithAlphaComponent:0.4f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(pipRect, -2.0f, -2.0f)] fill];
    
    // Solid pip
    [neon setFill];
    [[NSBezierPath bezierPathWithOvalInRect:pipRect] fill];
    
    // White specular center
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(pipRect, 1.2f, 1.2f)] fill];
    
    // 6. Labels (Title & Formatted Value)
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    
    // Title
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9.5f],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.75f green:0.78f blue:0.85f alpha:1.0f],
        NSParagraphStyleAttributeName: style
    };
    NSRect titleRect = NSMakeRect(0, 16.0f, w, 14.0f);
    [_titleText drawInRect:titleRect withAttributes:titleAttrs];
    
    // Formatted Value
    NSString *valStr = [NSString stringWithFormat:@"%.0f%@", _knobValue, _unitText ?: @""];
    if (_maxValue - _minValue < 15.0f) {
        valStr = [NSString stringWithFormat:@"%.1f%@", _knobValue, _unitText ?: @""];
    }
    
    NSDictionary *valAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: neon,
        NSParagraphStyleAttributeName: style
    };
    NSRect valRect = NSMakeRect(0, 2.0f, w, 14.0f);
    [valStr drawInRect:valRect withAttributes:valAttrs];
}

@end
