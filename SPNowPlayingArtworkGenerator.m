//
//  SPNowPlayingArtworkGenerator.m
//  SIDPLAY
//
//  Created for Milestone 5.2: System Media Keys & macOS Now Playing Integration.
//

#import "SPNowPlayingArtworkGenerator.h"

static NSCache<NSString *, NSImage *> *sArtworkCache = nil;

@implementation SPNowPlayingArtworkGenerator

+ (void)initialize {
    if (self == [SPNowPlayingArtworkGenerator class]) {
        sArtworkCache = [[NSCache alloc] init];
        sArtworkCache.countLimit = 20; // Keep up to 20 cached album covers in memory
    }
}

+ (NSImage *)artworkForTitle:(NSString *)title
                      artist:(NSString *)artist
                       isMod:(BOOL)isMod
                   chipModel:(NSString *)chipModel
                     subtune:(int)subtune
                subtuneCount:(int)subtuneCount
                        size:(CGSize)size
{
    CGFloat w = (size.width > 120.0f) ? size.width : 600.0f;
    CGFloat h = (size.height > 120.0f) ? size.height : 600.0f;
    NSSize targetSize = NSMakeSize(w, h);
    
    NSString *safeTitle = (title && title.length > 0) ? title : @"Untitled";
    NSString *safeArtist = (artist && artist.length > 0) ? artist : @"Unknown Artist";
    NSString *safeChip = (chipModel && chipModel.length > 0) ? chipModel : (isMod ? @"PAULA 8364" : @"MOS 6581");
    
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%@_%@_%d_%d_%d_%dx%d",
                          safeTitle, safeArtist, safeChip, isMod, subtune, subtuneCount, (int)w, (int)h];
    
    NSImage *cached = [sArtworkCache objectForKey:cacheKey];
    if (cached) {
        return cached;
    }
    
    NSImage *image = [NSImage imageWithSize:targetSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        
        if (isMod) {
            [self drawAmigaArtworkInRect:dstRect
                                   title:safeTitle
                                  artist:safeArtist
                               chipModel:safeChip
                                 subtune:subtune
                            subtuneCount:subtuneCount
                                 context:ctx];
        } else {
            [self drawC64ArtworkInRect:dstRect
                                 title:safeTitle
                                artist:safeArtist
                             chipModel:safeChip
                               subtune:subtune
                          subtuneCount:subtuneCount
                               context:ctx];
        }
        return YES;
    }];
    
    if (image) {
        [sArtworkCache setObject:image forKey:cacheKey];
    }
    return image;
}

#pragma mark - Amiga Boing Ball Artwork Drawing

+ (void)drawAmigaArtworkInRect:(NSRect)rect
                         title:(NSString *)title
                        artist:(NSString *)artist
                     chipModel:(NSString *)chipModel
                       subtune:(int)subtune
                  subtuneCount:(int)subtuneCount
                       context:(CGContextRef)ctx
{
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    
    // 1. Deep Amiga night gradient background
    NSColor *bgTop = [NSColor colorWithCalibratedRed:0.04f green:0.06f blue:0.13f alpha:1.0f];
    NSColor *bgBot = [NSColor colorWithCalibratedRed:0.11f green:0.14f blue:0.24f alpha:1.0f];
    NSGradient *bgGrad = [[NSGradient alloc] initWithStartingColor:bgTop endingColor:bgBot];
    [bgGrad drawInRect:rect angle:-90.0f];
    
    // 2. 3D Perspective Purple Wireframe Grid
    CGFloat horizonY = h * 0.40f;
    NSColor *gridColor = [NSColor colorWithCalibratedRed:0.68f green:0.24f blue:0.95f alpha:0.35f];
    [gridColor setStroke];
    
    // Horizontal lines with exponential perspective compression
    for (CGFloat f = 0.0f; f <= 1.0f; f += 0.10f) {
        CGFloat y = horizonY * (1.0f - powf(f, 2.0f));
        NSBezierPath *hLine = [NSBezierPath bezierPath];
        [hLine moveToPoint:NSMakePoint(0, y)];
        [hLine lineToPoint:NSMakePoint(w, y)];
        [hLine setLineWidth:1.0f];
        [hLine stroke];
    }
    
    // Perspective radial lines converging to center vanishing point on horizon
    NSPoint vp = NSMakePoint(w * 0.5f, horizonY);
    int numGridV = 16;
    for (int i = 0; i <= numGridV; i++) {
        CGFloat bottomX = (w / numGridV) * i;
        NSBezierPath *vLine = [NSBezierPath bezierPath];
        [vLine moveToPoint:vp];
        [vLine lineToPoint:NSMakePoint(bottomX, 0)];
        [vLine setLineWidth:1.0f];
        [vLine stroke];
    }
    
    // 3. Drop Shadow for Boing Ball
    CGFloat ballRadius = w * 0.22f;
    NSPoint ballCenter = NSMakePoint(w * 0.5f, h * 0.58f);
    
    NSRect shadowRect = NSMakeRect(ballCenter.x - ballRadius * 0.85f, horizonY - 14.0f, ballRadius * 1.7f, 22.0f);
    NSColor *shadowColor = [NSColor colorWithCalibratedRed:0.02f green:0.02f blue:0.05f alpha:0.65f];
    [shadowColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:shadowRect] fill];
    
    // 4. 3D Amiga Boing Ball (Checkered Sphere)
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(ballCenter.x - ballRadius, ballCenter.y - ballRadius, ballRadius * 2, ballRadius * 2));
    CGContextClip(ctx);
    
    // Base sphere fill with warm specular shading
    NSColor *redFacet = [NSColor colorWithCalibratedRed:0.86f green:0.12f blue:0.12f alpha:1.0f];
    NSColor *whiteFacet = [NSColor colorWithCalibratedRed:0.96f green:0.96f blue:0.98f alpha:1.0f];
    
    int latBands = 8;
    int lonBands = 12;
    for (int lat = 0; lat < latBands; lat++) {
        CGFloat y0 = ballCenter.y - ballRadius + (2.0f * ballRadius / latBands) * lat;
        CGFloat y1 = ballCenter.y - ballRadius + (2.0f * ballRadius / latBands) * (lat + 1);
        
        for (int lon = 0; lon < lonBands; lon++) {
            BOOL isRed = ((lat + lon) % 2 == 0);
            NSColor *c = isRed ? redFacet : whiteFacet;
            
            CGFloat x0 = ballCenter.x - ballRadius + (2.0f * ballRadius / lonBands) * lon;
            CGFloat x1 = ballCenter.x - ballRadius + (2.0f * ballRadius / lonBands) * (lon + 1);
            
            [c setFill];
            NSRectFill(NSMakeRect(x0, y0, x1 - x0, y1 - y0));
        }
    }
    
    // Inner Sphere Radial Lighting (Upper-left shine to lower-right shadow)
    NSColor *shine = [NSColor colorWithCalibratedWhite:1.0f alpha:0.45f];
    NSColor *deepShadow = [NSColor colorWithCalibratedWhite:0.0f alpha:0.70f];
    NSColor *clear = [NSColor colorWithCalibratedWhite:0.0f alpha:0.0f];
    
    NSGradient *sphereGrad = [[NSGradient alloc] initWithColorsAndLocations:
                              shine, 0.0f,
                              clear, 0.55f,
                              deepShadow, 1.0f, nil];
    [sphereGrad drawFromCenter:NSMakePoint(ballCenter.x - ballRadius * 0.35f, ballCenter.y + ballRadius * 0.35f)
                        radius:0.0f
                      toCenter:ballCenter
                        radius:ballRadius
                       options:0];
    
    CGContextRestoreGState(ctx);
    
    // 5. Silicon Chip Badge at Top (Paula 8364 with amber LED)
    [self drawSiliconBadgeWithText:[NSString stringWithFormat:@"[ %@ ]", chipModel]
                          ledColor:[NSColor colorWithCalibratedRed:1.0f green:0.65f blue:0.0f alpha:1.0f]
                            center:NSMakePoint(w * 0.5f, h - 38.0f)
                             width:w * 0.44f];
    
    // 6. Bottom Metadata Card Overlay (Frosted rounded container)
    NSRect cardRect = NSMakeRect(24.0f, 20.0f, w - 48.0f, h * 0.26f);
    NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:14.0f yRadius:14.0f];
    [[NSColor colorWithCalibratedRed:0.08f green:0.10f blue:0.18f alpha:0.85f] setFill];
    [cardPath fill];
    [[NSColor colorWithCalibratedRed:0.40f green:0.45f blue:0.65f alpha:0.35f] setStroke];
    [cardPath setLineWidth:1.0f];
    [cardPath stroke];
    
    // Song Title
    NSMutableParagraphStyle *styleCenter = [[NSMutableParagraphStyle alloc] init];
    styleCenter.alignment = NSTextAlignmentCenter;
    styleCenter.lineBreakMode = NSLineBreakByTruncatingTail;
    
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:w * 0.048f],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect titleRect = NSMakeRect(cardRect.origin.x + 12.0f, cardRect.origin.y + cardRect.size.height - 42.0f, cardRect.size.width - 24.0f, 30.0f);
    [title drawInRect:titleRect withAttributes:titleAttrs];
    
    // Artist
    NSDictionary *artistAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:w * 0.038f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0f green:0.68f blue:0.25f alpha:1.0f], // Topaz amber
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect artistRect = NSMakeRect(cardRect.origin.x + 12.0f, titleRect.origin.y - 28.0f, cardRect.size.width - 24.0f, 24.0f);
    [artist drawInRect:artistRect withAttributes:artistAttrs];
    
    // Subtune / Format info
    NSString *subtuneStr = (subtuneCount > 1) ?
        [NSString stringWithFormat:@"Song %d of %d  •  Amiga ProTracker / FastTracker", subtune, subtuneCount] :
        @"Amiga Module  •  CSG 8364 Paula Audio";
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:w * 0.026f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.70f green:0.75f blue:0.88f alpha:0.80f],
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect subRect = NSMakeRect(cardRect.origin.x + 12.0f, artistRect.origin.y - 24.0f, cardRect.size.width - 24.0f, 20.0f);
    [subtuneStr drawInRect:subRect withAttributes:subAttrs];
}

#pragma mark - Commodore 64 Cassette Artwork Drawing

+ (void)drawC64ArtworkInRect:(NSRect)rect
                       title:(NSString *)title
                      artist:(NSString *)artist
                   chipModel:(NSString *)chipModel
                     subtune:(int)subtune
                subtuneCount:(int)subtuneCount
                     context:(CGContextRef)ctx
{
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    
    // 1. C64 Classic Deep Purple / Border Gradient
    NSColor *c64Top = [NSColor colorWithCalibratedRed:0.20f green:0.14f blue:0.42f alpha:1.0f]; // Deep border
    NSColor *c64Bot = [NSColor colorWithCalibratedRed:0.09f green:0.06f blue:0.22f alpha:1.0f];
    NSGradient *bgGrad = [[NSGradient alloc] initWithStartingColor:c64Top endingColor:c64Bot];
    [bgGrad drawInRect:rect angle:-90.0f];
    
    // 2. Subtle vintage CRT scanline texture
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.08f] setFill];
    for (CGFloat y = 0.0f; y < h; y += 4.0f) {
        NSRectFill(NSMakeRect(0, y, w, 1.5f));
    }
    
    // 3. Centerpiece: Commodore Datasette C-60 Compact Cassette
    CGFloat cassW = w * 0.74f;
    CGFloat cassH = h * 0.44f;
    CGFloat cassX = (w - cassW) * 0.5f;
    CGFloat cassY = h * 0.42f;
    NSRect cassRect = NSMakeRect(cassX, cassY, cassW, cassH);
    
    // Drop shadow under cassette
    NSRect cassShadow = NSMakeRect(cassX + 6.0f, cassY - 12.0f, cassW, cassH);
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.55f] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:cassShadow xRadius:12.0f yRadius:12.0f] fill];
    
    // Cassette shell body (Dark matte graphite)
    NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:cassRect xRadius:10.0f yRadius:10.0f];
    [[NSColor colorWithCalibratedRed:0.14f green:0.15f blue:0.18f alpha:1.0f] setFill];
    [shell fill];
    [[NSColor colorWithCalibratedRed:0.28f green:0.30f blue:0.35f alpha:1.0f] setStroke];
    [shell setLineWidth:1.5f];
    [shell stroke];
    
    // 4 Corner screws
    NSColor *screwCol = [NSColor colorWithCalibratedRed:0.55f green:0.58f blue:0.65f alpha:1.0f];
    [screwCol setFill];
    CGFloat pad = 10.0f;
    CGFloat screwD = 6.0f;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cassX + pad, cassY + pad, screwD, screwD)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cassX + cassW - pad - screwD, cassY + pad, screwD, screwD)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cassX + pad, cassY + cassH - pad - screwD, screwD, screwD)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cassX + cassW - pad - screwD, cassY + cassH - pad - screwD, screwD, screwD)] fill];
    
    // Cassette Label (Cream / Off-White)
    CGFloat lblW = cassW * 0.88f;
    CGFloat lblH = cassH * 0.68f;
    CGFloat lblX = cassX + (cassW - lblW) * 0.5f;
    CGFloat lblY = cassY + (cassH - lblH) * 0.5f + 6.0f;
    NSRect lblRect = NSMakeRect(lblX, lblY, lblW, lblH);
    NSBezierPath *lblPath = [NSBezierPath bezierPathWithRoundedRect:lblRect xRadius:6.0f yRadius:6.0f];
    [[NSColor colorWithCalibratedRed:0.94f green:0.93f blue:0.89f alpha:1.0f] setFill];
    [lblPath fill];
    
    // Commodore 5-color Rainbow Stripe on Label Header
    CGFloat stripeH = 4.0f;
    CGFloat stripeY = lblY + lblH - 12.0f;
    NSArray *rainbow = @[
        [NSColor colorWithCalibratedRed:0.82f green:0.24f blue:0.24f alpha:1.0f], // Red
        [NSColor colorWithCalibratedRed:0.88f green:0.48f blue:0.18f alpha:1.0f], // Orange
        [NSColor colorWithCalibratedRed:0.92f green:0.75f blue:0.18f alpha:1.0f], // Yellow
        [NSColor colorWithCalibratedRed:0.28f green:0.68f blue:0.35f alpha:1.0f], // Green
        [NSColor colorWithCalibratedRed:0.22f green:0.68f blue:0.82f alpha:1.0f]  // Cyan
    ];
    CGFloat segW = lblW / rainbow.count;
    for (NSUInteger i = 0; i < rainbow.count; i++) {
        [rainbow[i] setFill];
        NSRectFill(NSMakeRect(lblX + i * segW, stripeY, segW, stripeH));
    }
    
    // Label Header Text
    NSDictionary *lblHeaderAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9.0f],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.18f green:0.20f blue:0.28f alpha:1.0f]
    };
    [@"COMMODORE C-60 AUDIO CASSETTE" drawAtPoint:NSMakePoint(lblX + 10.0f, stripeY - 14.0f) withAttributes:lblHeaderAttrs];
    
    // Tape Window Cutout in Center
    CGFloat winW = lblW * 0.58f;
    CGFloat winH = lblH * 0.44f;
    CGFloat winX = lblX + (lblW - winW) * 0.5f;
    CGFloat winY = lblY + (lblH - winH) * 0.5f - 8.0f;
    NSRect winRect = NSMakeRect(winX, winY, winW, winH);
    NSBezierPath *winPath = [NSBezierPath bezierPathWithRoundedRect:winRect xRadius:8.0f yRadius:8.0f];
    [[NSColor colorWithCalibratedRed:0.08f green:0.09f blue:0.11f alpha:0.90f] setFill];
    [winPath fill];
    [[NSColor colorWithCalibratedRed:0.35f green:0.38f blue:0.42f alpha:1.0f] setStroke];
    [winPath setLineWidth:1.0f];
    [winPath stroke];
    
    // Dual White Spool Hubs & Brown Magnetic Tape
    CGFloat spoolRadius = winH * 0.32f;
    CGFloat spoolY = winY + (winH - spoolRadius * 2) * 0.5f;
    CGFloat leftSpoolX = winX + winW * 0.22f - spoolRadius;
    CGFloat rightSpoolX = winX + winW * 0.78f - spoolRadius;
    
    // Brown tape bridge
    NSRect tapeBridge = NSMakeRect(leftSpoolX + spoolRadius, winY + winH * 0.35f, rightSpoolX - leftSpoolX, winH * 0.30f);
    [[NSColor colorWithCalibratedRed:0.36f green:0.22f blue:0.14f alpha:1.0f] setFill];
    NSRectFill(tapeBridge);
    
    // Spools
    [[NSColor colorWithCalibratedWhite:0.95f alpha:1.0f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(leftSpoolX, spoolY, spoolRadius * 2, spoolRadius * 2)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(rightSpoolX, spoolY, spoolRadius * 2, spoolRadius * 2)] fill];
    
    // Spool Centers
    [[NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:1.0f] setFill];
    CGFloat centerR = spoolRadius * 0.45f;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(leftSpoolX + spoolRadius - centerR, spoolY + spoolRadius - centerR, centerR * 2, centerR * 2)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(rightSpoolX + spoolRadius - centerR, spoolY + spoolRadius - centerR, centerR * 2, centerR * 2)] fill];
    
    // 4. Silicon Chip Badge at Top
    BOOL isDual = [chipModel containsString:@"2x"] || [chipModel containsString:@"DUAL"];
    NSColor *chipLed = isDual ?
        [NSColor colorWithCalibratedRed:0.0f green:0.90f blue:1.0f alpha:1.0f] : // Electric cyan
        [NSColor colorWithCalibratedRed:0.0f green:0.90f blue:0.45f alpha:1.0f]; // Emerald green
    [self drawSiliconBadgeWithText:[NSString stringWithFormat:@"[ %@ ]", chipModel]
                          ledColor:chipLed
                            center:NSMakePoint(w * 0.5f, h - 38.0f)
                             width:w * 0.44f];
    
    // 5. Bottom Metadata Card Overlay
    NSRect cardRect = NSMakeRect(24.0f, 20.0f, w - 48.0f, h * 0.26f);
    NSBezierPath *cardPath = [NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:14.0f yRadius:14.0f];
    [[NSColor colorWithCalibratedRed:0.12f green:0.09f blue:0.24f alpha:0.90f] setFill]; // C64 screen blue
    [cardPath fill];
    [[NSColor colorWithCalibratedRed:0.35f green:0.28f blue:0.65f alpha:0.50f] setStroke];
    [cardPath setLineWidth:1.0f];
    [cardPath stroke];
    
    NSMutableParagraphStyle *styleCenter = [[NSMutableParagraphStyle alloc] init];
    styleCenter.alignment = NSTextAlignmentCenter;
    styleCenter.lineBreakMode = NSLineBreakByTruncatingTail;
    
    // Title in C64 Lavender
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:w * 0.048f],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.65f green:0.65f blue:1.0f alpha:1.0f], // C64 lavender
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect titleRect = NSMakeRect(cardRect.origin.x + 12.0f, cardRect.origin.y + cardRect.size.height - 42.0f, cardRect.size.width - 24.0f, 30.0f);
    [title drawInRect:titleRect withAttributes:titleAttrs];
    
    // Composer in C64 VIC-II Yellow
    NSDictionary *artistAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:w * 0.038f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.93f green:0.93f blue:0.47f alpha:1.0f], // VIC-II yellow
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect artistRect = NSMakeRect(cardRect.origin.x + 12.0f, titleRect.origin.y - 28.0f, cardRect.size.width - 24.0f, 24.0f);
    [artist drawInRect:artistRect withAttributes:artistAttrs];
    
    // Subtune / Hardware info
    NSString *subtuneStr = (subtuneCount > 1) ?
        [NSString stringWithFormat:@"Subtune %d of %d  •  %@  •  Commodore 64", subtune, subtuneCount, chipModel] :
        [NSString stringWithFormat:@"Commodore 64 SID  •  %@", chipModel];
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:w * 0.026f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.75f green:0.75f blue:0.90f alpha:0.80f],
        NSParagraphStyleAttributeName: styleCenter
    };
    NSRect subRect = NSMakeRect(cardRect.origin.x + 12.0f, artistRect.origin.y - 24.0f, cardRect.size.width - 24.0f, 20.0f);
    [subtuneStr drawInRect:subRect withAttributes:subAttrs];
}

#pragma mark - Shared Silicon Chip Badge

+ (void)drawSiliconBadgeWithText:(NSString *)badgeText
                        ledColor:(NSColor *)ledColor
                          center:(NSPoint)center
                           width:(CGFloat)width
{
    CGFloat h = 26.0f;
    NSRect badgeRect = NSMakeRect(center.x - width * 0.5f, center.y - h * 0.5f, width, h);
    
    // Chip body
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:6.0f yRadius:6.0f];
    [[NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:0.92f] setFill];
    [pill fill];
    [[NSColor colorWithCalibratedRed:0.30f green:0.32f blue:0.38f alpha:0.80f] setStroke];
    [pill setLineWidth:1.0f];
    [pill stroke];
    
    // Glowing LED Dot
    CGFloat ledD = 8.0f;
    CGFloat ledX = badgeRect.origin.x + 12.0f;
    CGFloat ledY = badgeRect.origin.y + (h - ledD) * 0.5f;
    
    // Soft outer glow
    [[ledColor colorWithAlphaComponent:0.35f] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ledX - 2.0f, ledY - 2.0f, ledD + 4.0f, ledD + 4.0f)] fill];
    
    // Solid LED core
    [ledColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ledX, ledY, ledD, ledD)] fill];
    
    // Center white specular glint
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ledX + 2.0f, ledY + 3.5f, 2.5f, 2.5f)] fill];
    
    // Embossed Chip Text
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.5f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.88f green:0.90f blue:0.95f alpha:1.0f],
        NSParagraphStyleAttributeName: style
    };
    NSRect textRect = NSMakeRect(badgeRect.origin.x + 24.0f, badgeRect.origin.y + 4.5f, badgeRect.size.width - 32.0f, 18.0f);
    [badgeText drawInRect:textRect withAttributes:attrs];
}

@end
