//
//  SPToggleSwitchControl.m
//  SIDPLAY
//
//  Non-standard tactile chrome bat toggle switch control with mechanical
//  spring action, mounting nut, and status LED.
//

#import "SPToggleSwitchControl.h"

@interface SPToggleSwitchControl () {
    BOOL _isPressed;
}
@end

@implementation SPToggleSwitchControl

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect
                         title:@"SWITCH"
                          isOn:NO
                      ledColor:SPToggleLedColorEmerald];
}

- (instancetype)initWithFrame:(NSRect)frameRect
                        title:(NSString *)title
                         isOn:(BOOL)isOn
                     ledColor:(SPToggleLedColor)color
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _titleText = [title copy];
        _isOn = isOn;
        _ledColor = color;
    }
    return self;
}

- (void)setIsOn:(BOOL)isOn {
    if (_isOn != isOn) {
        _isOn = isOn;
        [self setNeedsDisplay:YES];
    }
}

- (NSInteger)state {
    return _isOn ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setState:(NSInteger)state {
    self.isOn = (state == NSControlStateValueOn);
}

- (NSColor *)neonColor {
    switch (_ledColor) {
        case SPToggleLedColorCyan:
            return [NSColor colorWithCalibratedRed:0.0f green:0.94f blue:1.0f alpha:1.0f];
        case SPToggleLedColorAmber:
            return [NSColor colorWithCalibratedRed:1.0f green:0.65f blue:0.10f alpha:1.0f];
        case SPToggleLedColorEmerald:
            return [NSColor colorWithCalibratedRed:0.22f green:1.0f blue:0.35f alpha:1.0f];
        case SPToggleLedColorRed:
            return [NSColor colorWithCalibratedRed:1.0f green:0.25f blue:0.25f alpha:1.0f];
    }
}

#pragma mark - Mouse Tracking

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    _isPressed = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.isEnabled) return;
    _isPressed = NO;
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        self.isOn = !self.isOn;
        [self sendAction:self.action to:self.target];
    }
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    NSRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    CGFloat labelAreaHeight = 26.0f;
    CGFloat switchAreaHeight = h - labelAreaHeight;
    CGFloat switchCenterY = h - (switchAreaHeight * 0.5f);
    CGFloat centerX = w * 0.5f;
    
    // 1. Threaded Mounting Nut / Base Plate
    CGFloat nutRadius = 14.0f;
    NSRect nutRect = NSMakeRect(centerX - nutRadius, switchCenterY - nutRadius, nutRadius * 2.0f, nutRadius * 2.0f);
    
    // Outer Nut Rim (Metal gradient)
    NSColor *nutTop = [NSColor colorWithCalibratedRed:0.38f green:0.40f blue:0.48f alpha:1.0f];
    NSColor *nutBot = [NSColor colorWithCalibratedRed:0.16f green:0.18f blue:0.22f alpha:1.0f];
    NSGradient *nutGrad = [[NSGradient alloc] initWithStartingColor:nutTop endingColor:nutBot];
    [nutGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:nutRect] angle:-45.0f];
    
    [[NSColor colorWithCalibratedRed:0.50f green:0.54f blue:0.62f alpha:0.9f] setStroke];
    NSBezierPath *nutBorder = [NSBezierPath bezierPathWithOvalInRect:nutRect];
    nutBorder.lineWidth = 1.0f;
    [nutBorder stroke];
    
    // 2. Recessed Switch Slot (Dark Hole)
    CGFloat slotW = 10.0f;
    CGFloat slotH = 22.0f;
    NSRect slotRect = NSMakeRect(centerX - slotW * 0.5f, switchCenterY - slotH * 0.5f, slotW, slotH);
    NSBezierPath *slotPath = [NSBezierPath bezierPathWithRoundedRect:slotRect xRadius:5.0f yRadius:5.0f];
    [[NSColor colorWithCalibratedRed:0.04f green:0.05f blue:0.07f alpha:1.0f] setFill];
    [slotPath fill];
    [[NSColor colorWithCalibratedRed:0.22f green:0.24f blue:0.28f alpha:1.0f] setStroke];
    slotPath.lineWidth = 1.0f;
    [slotPath stroke];
    
    // 3. Chrome Bat (Lever)
    // When ON: points UP. When OFF: points DOWN.
    CGFloat batW = 7.0f;
    CGFloat batH = 14.0f;
    CGFloat batTipRadius = 5.0f;
    
    CGFloat batY = _isOn ? (switchCenterY + 1.0f) : (switchCenterY - batH - 1.0f);
    if (_isPressed) {
        batY += _isOn ? -3.0f : 3.0f;
    }
    
    NSRect batRect = NSMakeRect(centerX - batW * 0.5f, batY, batW, batH);
    
    // Drop shadow
    NSRect batShadow = NSMakeRect(batRect.origin.x + 1.0f, batRect.origin.y - 2.0f, batW, batH);
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.6f] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:batShadow xRadius:3.5f yRadius:3.5f] fill];
    
    // Chrome Lever Body
    NSBezierPath *batPath = [NSBezierPath bezierPathWithRoundedRect:batRect xRadius:3.5f yRadius:3.5f];
    NSColor *batTop = [NSColor colorWithCalibratedRed:0.92f green:0.93f blue:0.96f alpha:1.0f];
    NSColor *batBot = [NSColor colorWithCalibratedRed:0.45f green:0.48f blue:0.55f alpha:1.0f];
    NSGradient *batGrad = [[NSGradient alloc] initWithStartingColor:batTop endingColor:batBot];
    [batGrad drawInBezierPath:batPath angle:_isOn ? 90.0f : -90.0f];
    
    // Cylindrical bat tip ball
    CGFloat tipCenterY = _isOn ? (batY + batH - 2.0f) : (batY + 2.0f);
    NSRect tipRect = NSMakeRect(centerX - batTipRadius, tipCenterY - batTipRadius, batTipRadius * 2.0f, batTipRadius * 2.0f);
    NSColor *tipShine = [NSColor colorWithCalibratedWhite:1.0f alpha:1.0f];
    NSColor *tipBase = [NSColor colorWithCalibratedRed:0.65f green:0.68f blue:0.75f alpha:1.0f];
    NSGradient *tipGrad = [[NSGradient alloc] initWithStartingColor:tipShine endingColor:tipBase];
    [tipGrad drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:tipRect] angle:-45.0f];
    
    // 4. Status Indicator LED (Micro dot above slot)
    CGFloat ledD = 5.0f;
    CGFloat ledY = switchCenterY + nutRadius + 4.0f;
    if (ledY + ledD < h) {
        NSRect ledRect = NSMakeRect(centerX - ledD * 0.5f, ledY, ledD, ledD);
        NSColor *neon = [self neonColor];
        
        if (_isOn) {
            // Glow
            [[neon colorWithAlphaComponent:0.45f] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(ledRect, -2.0f, -2.0f)] fill];
            [neon setFill];
            [[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];
            [[NSColor whiteColor] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(ledRect, 1.2f, 1.2f)] fill];
        } else {
            // Dim unlit LED
            [[NSColor colorWithCalibratedRed:0.15f green:0.17f blue:0.20f alpha:1.0f] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];
        }
    }
    
    // 5. Labels (Title & Status)
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    
    // Title
    NSFont *titleFont = [NSFont boldSystemFontOfSize:9.5f] ?: [NSFont systemFontOfSize:9.5f];
    NSMutableDictionary *titleAttrs = [NSMutableDictionary dictionaryWithCapacity:3];
    if (titleFont) titleAttrs[NSFontAttributeName] = titleFont;
    titleAttrs[NSForegroundColorAttributeName] = [NSColor colorWithCalibratedRed:0.75f green:0.78f blue:0.85f alpha:1.0f];
    if (style) titleAttrs[NSParagraphStyleAttributeName] = style;
    NSRect titleRect = NSMakeRect(0, 14.0f, w, 13.0f);
    [_titleText drawInRect:titleRect withAttributes:titleAttrs];
    
    // ON / OFF text
    NSString *statusStr = _isOn ? @"ON" : @"OFF";
    NSColor *statusColor = _isOn ? [self neonColor] : [NSColor colorWithCalibratedRed:0.45f green:0.48f blue:0.55f alpha:1.0f];
    NSFont *statusFont = [NSFont monospacedDigitSystemFontOfSize:9.5f weight:NSFontWeightBold] ?: [NSFont boldSystemFontOfSize:9.5f] ?: [NSFont systemFontOfSize:9.5f];
    NSMutableDictionary *statusAttrs = [NSMutableDictionary dictionaryWithCapacity:3];
    if (statusFont) statusAttrs[NSFontAttributeName] = statusFont;
    if (statusColor) statusAttrs[NSForegroundColorAttributeName] = statusColor;
    if (style) statusAttrs[NSParagraphStyleAttributeName] = style;
    NSRect statusRect = NSMakeRect(0, 1.0f, w, 12.0f);
    [statusStr drawInRect:statusRect withAttributes:statusAttrs];
}

@end
