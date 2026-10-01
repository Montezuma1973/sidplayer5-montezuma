//
//  SPNixieDisplayView.m
//  SIDPLAY
//
//  Warm glowing neon Nixie tube display view with cylindrical glass
//  envelopes, internal wire anode grids, and filament glow.
//

#import "SPNixieDisplayView.h"

@implementation SPNixieDisplayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _seconds = 0;
        _subtune = 1;
        _subtuneCount = 1;
        _showSubtune = NO;
    }
    return self;
}

- (void)setTimeInSeconds:(NSInteger)sec {
    if (_seconds != sec) {
        _seconds = sec;
        [self setNeedsDisplay:YES];
    }
}

- (void)setSubtune:(int)subtune count:(int)count {
    if (_subtune != subtune || _subtuneCount != count) {
        _subtune = subtune;
        _subtuneCount = count;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    if (self.clickHandler) {
        self.clickHandler(self);
    } else if (self.allowToggleOnMouseDown) {
        self.showSubtune = !self.showSubtune;
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    // Background chassis cutout
    NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0f yRadius:8.0f];
    [[NSColor colorWithCalibratedRed:0.04f green:0.05f blue:0.06f alpha:0.95f] setFill];
    [bgPath fill];
    [[NSColor colorWithCalibratedRed:0.18f green:0.20f blue:0.25f alpha:0.8f] setStroke];
    bgPath.lineWidth = 1.0f;
    [bgPath stroke];
    
    // Header Label (Top badge)
    NSMutableParagraphStyle *hdrStyle = [[NSMutableParagraphStyle alloc] init];
    hdrStyle.alignment = NSTextAlignmentCenter;
    NSDictionary *hdrAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:9.0f weight:NSFontWeightHeavy],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0f green:0.80f blue:0.35f alpha:0.95f],
        NSParagraphStyleAttributeName: hdrStyle
    };
    NSString *hdrText = _customLabel ?: (_showSubtune ? @"SUBTUNE SONG" : @"TRACK TIME");
    [hdrText drawInRect:NSMakeRect(0, h - 14.0f, w, 12.0f) withAttributes:hdrAttrs];
    
    // Sub-Label (Bottom annotation)
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:7.5f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.60f green:0.78f blue:0.88f alpha:0.90f],
        NSParagraphStyleAttributeName: hdrStyle
    };
    NSString *subText = _subLabel ?: (_showSubtune ? @"CURRENT / TOTAL" : @"MINUTES : SECONDS");
    [subText drawInRect:NSMakeRect(0, 1.0f, w, 10.0f) withAttributes:subAttrs];
    
    // Determine 4 digits & separator
    NSString *d1 = @"0", *d2 = @"0", *sep = @":", *d3 = @"0", *d4 = @"0";
    if (_showSubtune) {
        int sub = MAX(1, _subtune);
        int tot = MAX(1, _subtuneCount);
        d1 = [NSString stringWithFormat:@"%d", (sub / 10) % 10];
        d2 = [NSString stringWithFormat:@"%d", sub % 10];
        sep = @"/";
        d3 = [NSString stringWithFormat:@"%d", (tot / 10) % 10];
        d4 = [NSString stringWithFormat:@"%d", tot % 10];
    } else {
        NSInteger m = _seconds / 60;
        NSInteger s = _seconds % 60;
        if (m > 99) m = 99;
        d1 = [NSString stringWithFormat:@"%ld", (long)(m / 10)];
        d2 = [NSString stringWithFormat:@"%ld", (long)(m % 10)];
        d3 = [NSString stringWithFormat:@"%ld", (long)(s / 10)];
        d4 = [NSString stringWithFormat:@"%ld", (long)(s % 10)];
    }
    
    // Tubes layout: 4 tubes + 1 separator colon/slash
    CGFloat tubeMargin = 4.0f;
    CGFloat bottomPad = 12.0f;
    CGFloat topPad = 15.0f;
    CGFloat tubeH = h - bottomPad - topPad;
    CGFloat sepW = _showSubtune ? 14.0f : 12.0f;
    CGFloat tubeW = (w - (tubeMargin * 4.0f) - sepW - 8.0f) / 4.0f;
    if (tubeW > 36.0f) tubeW = 36.0f;
    if (tubeW < 12.0f) tubeW = 12.0f;
    
    CGFloat totalWidth = (tubeW * 4.0f) + sepW + (tubeMargin * 4.0f);
    CGFloat startX = (w - totalWidth) * 0.5f;
    if (startX < 4.0f) startX = 4.0f;
    CGFloat tubeY = bottomPad;
    
    // Tube 1
    NSRect t1Rect = NSMakeRect(startX, tubeY, tubeW, tubeH);
    [self drawNixieTubeInRect:t1Rect character:d1 isSeparator:NO context:ctx];
    
    // Tube 2
    NSRect t2Rect = NSMakeRect(startX + tubeW + tubeMargin, tubeY, tubeW, tubeH);
    [self drawNixieTubeInRect:t2Rect character:d2 isSeparator:NO context:ctx];
    
    // Separator Tube
    CGFloat sepX = startX + (tubeW * 2.0f) + (tubeMargin * 2.0f);
    NSRect sepRect = NSMakeRect(sepX, tubeY, sepW, tubeH);
    [self drawNixieTubeInRect:sepRect character:sep isSeparator:YES context:ctx];
    
    // Tube 3
    CGFloat t3X = sepX + sepW + tubeMargin;
    NSRect t3Rect = NSMakeRect(t3X, tubeY, tubeW, tubeH);
    [self drawNixieTubeInRect:t3Rect character:d3 isSeparator:NO context:ctx];
    
    // Tube 4
    CGFloat t4X = t3X + tubeW + tubeMargin;
    NSRect t4Rect = NSMakeRect(t4X, tubeY, tubeW, tubeH);
    [self drawNixieTubeInRect:t4Rect character:d4 isSeparator:NO context:ctx];
}

- (void)drawNixieTubeInRect:(NSRect)rect character:(NSString *)ch isSeparator:(BOOL)isSep context:(CGContextRef)ctx {
    CGFloat x = rect.origin.x;
    CGFloat y = rect.origin.y;
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    
    // 1. Ceramic Base Socket (Bottom)
    NSRect socketRect = NSMakeRect(x + 2.0f, y, w - 4.0f, 4.0f);
    [[NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:socketRect xRadius:2.0f yRadius:2.0f] fill];
    
    // 2. Glass Tube Envelope
    NSRect glassRect = NSMakeRect(x, y + 3.0f, w, h - 3.0f);
    NSBezierPath *glassPath = [NSBezierPath bezierPathWithRoundedRect:glassRect xRadius:w * 0.42f yRadius:w * 0.42f];
    
    // Dark glass interior with deep amber tint
    NSColor *glassDark = [NSColor colorWithCalibratedRed:0.06f green:0.04f blue:0.02f alpha:0.95f];
    [glassDark setFill];
    [glassPath fill];
    
    // Anode wire mesh grid inside tube
    CGContextSaveGState(ctx);
    [glassPath addClip];
    
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.04f] setStroke];
    for (CGFloat my = glassRect.origin.y; my < glassRect.origin.y + glassRect.size.height; my += 3.0f) {
        NSBezierPath *gridLine = [NSBezierPath bezierPath];
        [gridLine moveToPoint:NSMakePoint(x, my)];
        [gridLine lineToPoint:NSMakePoint(x + w, my)];
        gridLine.lineWidth = 0.5f;
        [gridLine stroke];
    }
    
    // 3. Glowing Neon Gas Character
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    
    CGFloat fontSize = isSep ? (h * 0.45f) : (h * 0.55f);
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightBold];
    
    NSRect textRect = NSMakeRect(x, y + (h - fontSize) * 0.45f, w, fontSize * 1.25f);
    
    // Pass 1: Soft orange outer glow aura
    NSDictionary *glowAttrs1 = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0f green:0.35f blue:0.0f alpha:0.35f],
        NSParagraphStyleAttributeName: style
    };
    [ch drawInRect:NSOffsetRect(textRect, 0, 0) withAttributes:glowAttrs1];
    
    // Pass 2: Bright warm orange bloom
    NSDictionary *glowAttrs2 = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0f green:0.55f blue:0.10f alpha:0.75f],
        NSParagraphStyleAttributeName: style
    };
    [ch drawInRect:textRect withAttributes:glowAttrs2];
    
    // Pass 3: Saturated filament core
    NSDictionary *coreAttrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0f green:0.85f blue:0.35f alpha:1.0f],
        NSParagraphStyleAttributeName: style
    };
    [ch drawInRect:textRect withAttributes:coreAttrs];
    
    // 4. Glass Reflection & Specular Highlights
    // Left edge glass reflection stroke
    NSBezierPath *leftShine = [NSBezierPath bezierPath];
    [leftShine moveToPoint:NSMakePoint(x + 2.5f, y + 8.0f)];
    [leftShine lineToPoint:NSMakePoint(x + 2.5f, y + h - 8.0f)];
    leftShine.lineWidth = 1.2f;
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.25f] setStroke];
    [leftShine stroke];
    
    // Right subtle bounce reflection
    NSBezierPath *rightShine = [NSBezierPath bezierPath];
    [rightShine moveToPoint:NSMakePoint(x + w - 2.5f, y + 8.0f)];
    [rightShine lineToPoint:NSMakePoint(x + w - 2.5f, y + h - 8.0f)];
    rightShine.lineWidth = 0.8f;
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.12f] setStroke];
    [rightShine stroke];
    
    CGContextRestoreGState(ctx);
    
    // Glass tube outer boundary outline
    [[NSColor colorWithCalibratedRed:0.30f green:0.28f blue:0.25f alpha:0.6f] setStroke];
    glassPath.lineWidth = 1.0f;
    [glassPath stroke];
}

@end
