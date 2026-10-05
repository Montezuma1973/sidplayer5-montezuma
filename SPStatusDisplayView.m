#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLMacro.h>
#import "SPPlayerWindow.h"
#import "SPMiniPlayerWindow.h"
#import "SPStatusDisplayView.h"
#import "NSImage+FlipImage.h"
#import "SPThemeManager.h"


@implementation SPQCView

// ----------------------------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frame
// ----------------------------------------------------------------------------
{
	NSOpenGLPixelFormatAttribute attributes[] =
	{
		NSOpenGLPFAAccelerated,
		NSOpenGLPFADoubleBuffer,
		0
	};

	NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];

    self = [super initWithFrame:frame pixelFormat:pixelFormat];
    if (self)
	{
		GLint zeroOpacity = 0;
		[self.openGLContext setValues:&zeroOpacity forParameter:NSOpenGLCPSurfaceOpacity];
		
		renderer = nil;
		rendererActive = NO;
        rendererVisible = NO;
	}
    return self;
}


// ----------------------------------------------------------------------------
- (void) prepareForQuit
// ----------------------------------------------------------------------------
{
	[self stopRendering];
    [NSThread sleepForTimeInterval:0.5f];
    renderer = nil;
}


// ----------------------------------------------------------------------------
- (BOOL)isOpaque
// ----------------------------------------------------------------------------
{
	return NO;
}


// ----------------------------------------------------------------------------
- (void) loadCompositionFromFile:(NSString*)path
// ----------------------------------------------------------------------------
{
	NSOpenGLContext* context = self.openGLContext;
    CGLContextObj cgl_ctx = (CGLContextObj) context.CGLContextObj;
    [context update];
    glViewport(0, 0, [self frame].size.width, [self frame].size.height);

    renderer = [[QCRenderer alloc] initWithOpenGLContext:self.openGLContext pixelFormat:self.pixelFormat file:path];
}


// ----------------------------------------------------------------------------
- (void) setEraseColor:(NSColor*)color
// ----------------------------------------------------------------------------
{
	eraseColor = color;
}


// ----------------------------------------------------------------------------
- (void) startRendering
// ----------------------------------------------------------------------------
{
	if (renderer == nil)
		return;
		
	if (rendererActive)
		return;
		
	rendererActive = YES;
	[NSThread detachNewThreadSelector:@selector(renderThread:) toTarget:self withObject:self];
}


// ----------------------------------------------------------------------------
- (void) stopRendering
// ----------------------------------------------------------------------------
{
	rendererActive = NO;
}


// ----------------------------------------------------------------------------
- (void) setRendererVisible:(BOOL)visible
// ----------------------------------------------------------------------------
{
    rendererVisible = visible;
}


// ----------------------------------------------------------------------------
- (void) renderThread:(id)object
// ----------------------------------------------------------------------------
{
    //NSLog(@"Rendering thread start");
    
    NSOpenGLContext* context = self.openGLContext;
    CGLContextObj cgl_ctx = (CGLContextObj) context.CGLContextObj;
    
    NSTimeInterval startTime = 0;
    int skipUpdateCount = 10;
    
    while (rendererActive && renderer != nil)
	{
        NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];

        if (skipUpdateCount == 0)
        {
            if (startTime == 0)
                startTime = time;
            // Make sure we draw to the right context
            [context makeCurrentContext];
            [context lock]; //CGLLockContext(cgl_ctx);
            glClearColor([eraseColor redComponent], [eraseColor greenComponent], [eraseColor blueComponent], [eraseColor alphaComponent]);
            glClear(GL_COLOR_BUFFER_BIT);
            
            if (rendererVisible)
                [renderer renderAtTime:(time - startTime) arguments:nil];
            
            [context flushBuffer];
            [context unlock]; //CGLUnlockContext(cgl_ctx);
        }
        else
            skipUpdateCount--;
        
		NSTimeInterval timeSpent = [NSDate timeIntervalSinceReferenceDate] - time;
		[NSThread sleepForTimeInterval:(1.0f/60.0f) - timeSpent];
	}
	
    //NSLog(@"Rendering thread exit");
	[NSThread exit];
}

@end




@implementation SPStatusDisplayView


// ----------------------------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frame
// ----------------------------------------------------------------------------
{
    self = [super initWithFrame:frame];
    if (self)
	{
		displayVisible = NO;
		resourcesLoaded = NO;
		showRemainingTime = NO;
		inStartState = YES;
		
		leftBackGroundImage = nil;
		middleBackGroundImage = nil;
		rightBackGroundImage = nil;
		timeDividerImage = nil;
		minusImage = nil;
		sidplayLogoImage = nil;

		leftArrowImage = nil;
		rightArrowImage = nil;
		mouseDownInLeftArrow = NO;
		mouseDownInRightArrow = NO;
		mouseDownInSubtuneInfo = NO;
		
		isHoveringScrubBar = NO;
		hoverScrubPositionX = 0;
		hoverScrubSeconds = -1;
		isDraggingScrub = NO;
		currentSubtuneCount = 1;
		scrubTrackingArea = nil;
		scrubBarFrame = NSZeroRect;
		loopBadgeFrame = NSZeroRect;
		
		currentPlaybackSeconds = -1;
		currentSonglengthInSeconds = -1;
		
		currentTimeDigits[0] = 0;
		currentTimeDigits[1] = 0;
		currentTimeDigits[2] = 0;
		currentTimeDigits[3] = 0;
			
		logoView = nil;
		logoVisible = YES;
		
		tuneInfo = nil;
	}
    return self;
}


// ----------------------------------------------------------------------------
- (void) setPlaybackSeconds:(NSInteger)seconds
// ----------------------------------------------------------------------------
{
	if (seconds == currentPlaybackSeconds)
		return;

	if (seconds >= 0)
		currentPlaybackSeconds = seconds;
	
	int remainingTime = (int)MAX(0, currentSonglengthInSeconds - currentPlaybackSeconds);
	
	int timeToShowInSeconds = (int)(showRemainingTime ? remainingTime: currentPlaybackSeconds);
	
	if (timeToShowInSeconds < 60)
	{
		currentTimeDigits[0] = 0;
		currentTimeDigits[1] = 0;
		currentTimeDigits[2] = timeToShowInSeconds / 10;
		currentTimeDigits[3] = timeToShowInSeconds - currentTimeDigits[2] * 10;
	} 
	else
	{
		int minutes = timeToShowInSeconds / 60;
		currentTimeDigits[0] = ( minutes / 10 ) % 10;
		currentTimeDigits[1] = minutes - currentTimeDigits[0] * 10;
		int tmp = timeToShowInSeconds - minutes * 60;
		currentTimeDigits[2] = tmp / 10;
		currentTimeDigits[3] = tmp - currentTimeDigits[2] * 10;
	}

	if (inStartState)
	{
		[self setLogoVisible:NO];
		displayVisible = YES;
		inStartState = NO;
	}
	[self setNeedsDisplay:YES];
}


// ----------------------------------------------------------------------------
- (void) setTitle:(NSString*)title andAuthor:(NSString*)author andReleaseInfo:(NSString*)releaseInfo andSubtune:(NSInteger)subtune ofSubtunes:(NSInteger)subtuneCount withSonglength:(int)timeInSeconds
// ----------------------------------------------------------------------------
{
	NSColor* color = [NSColor colorWithDeviceRed:0.298f green:0.298f blue:0.298f alpha:1.0f];
	NSDictionary* boldAttrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0f], 
																		 NSForegroundColorAttributeName: color};
	NSDictionary* normalAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:10.0f],
																		 NSForegroundColorAttributeName: color};
	
	tuneInfo = [[NSMutableAttributedString alloc] initWithString:title attributes:boldAttrs];
	NSAttributedString* additionalTuneInfo = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@\n%@", author, releaseInfo] attributes:normalAttrs];
	[tuneInfo appendAttributedString:additionalTuneInfo];
	
	NSMutableParagraphStyle* style = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
	style.alignment = NSTextAlignmentRight;
	
	NSDictionary* subtuneAttrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0f], 
																			NSParagraphStyleAttributeName: style,
																			NSForegroundColorAttributeName: color};
	subtuneInfo = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"Song %02ld of %02ld", (long)subtune, (long)subtuneCount] attributes:subtuneAttrs];
	currentSubtuneDigits[0] = subtune / 10;
	currentSubtuneDigits[1] = subtune % 10;
	subtuneCountDigits[0] = subtuneCount / 10;
	subtuneCountDigits[1] = subtuneCount % 10;

	currentSonglengthInSeconds = timeInSeconds;
	currentSubtuneCount = subtuneCount;
	[self setPlaybackSeconds:-1];

	if (inStartState)
	{
		[self setLogoVisible:NO];
		displayVisible = YES;
		inStartState = NO;
	}
	
	[self setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void) setChipBadge:(NSString*)chipName isMod:(BOOL)isMod
// ----------------------------------------------------------------------------
{
	chipBadge = [chipName copy];
	isModTune = isMod;
	[self setNeedsDisplay:YES];
}


// ----------------------------------------------------------------------------
- (void) loadResources
// ----------------------------------------------------------------------------
{
	inStartState = YES;
	
	leftBackGroundImage = [NSImage imageNamed:@"display_left"];
	middleBackGroundImage = [NSImage imageNamed:@"display_middle"];
	rightBackGroundImage = [NSImage imageNamed:@"display_right"];

	for (int i = 0; i < 10; i++)
	{
		smallNumberImages[i] = [NSImage imageNamed:[NSString stringWithFormat:@"numbersmall%d", i]];
		largeNumberImages[i] = [NSImage imageNamed:[NSString stringWithFormat:@"numberlarge%d", i]];
	}
	
	minusImage = [NSImage imageNamed:@"minus"];
	timeDividerImage = [NSImage imageNamed:@"timedivider"];
	
	leftArrowImage = [NSImage imageNamed:@"NSGoLeftTemplate"];
	rightArrowImage = [NSImage imageNamed:@"NSGoRightTemplate"];
	
	//sidplayLogoImage = [NSImage imageNamed:@"sidplay_logo"]; 
	
	//NSLog(@"%@: loading resources for window: %@\n", self, [self window]);
	
	if ([self.window isKindOfClass:[SPPlayerWindow class]] || [self.window isKindOfClass:[SPMiniPlayerWindow class]])
	{
		NSString* logoCompositionPath = [NSString stringWithFormat:@"%@%@",[NSBundle mainBundle].resourcePath,@"/logo.qtz"];

		logoView = [[SPQCView alloc] initWithFrame:self.frame];
		logoView.bounds = self.bounds;
		[logoView setEraseColor:[NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:0.0f]];

        [logoView loadCompositionFromFile:logoCompositionPath];
        
        [self addSubview:logoView positioned:NSWindowAbove relativeTo:self];
        [logoView startRendering];
        
        [self setLogoVisible:YES];
    }
		
	resourcesLoaded = YES;
}


// ----------------------------------------------------------------------------
- (void) prepareForQuit
// ----------------------------------------------------------------------------
{
    [logoView prepareForQuit];
    logoView = nil;
}


// ----------------------------------------------------------------------------
- (void) startLogoRendering
// ----------------------------------------------------------------------------
{
}


// ----------------------------------------------------------------------------
- (NSOpenGLView*) logoView;
// ----------------------------------------------------------------------------
{
	return logoView;
}


// ----------------------------------------------------------------------------
- (BOOL) displayVisible
// ----------------------------------------------------------------------------
{
	return displayVisible;
}


// ----------------------------------------------------------------------------
- (void) setDisplayVisible:(BOOL)visible
// ----------------------------------------------------------------------------
{
	displayVisible = visible;
}


// ----------------------------------------------------------------------------
- (BOOL) logoVisible
// ----------------------------------------------------------------------------
{
	return logoVisible;
}


// ----------------------------------------------------------------------------
- (void) setLogoVisible:(BOOL)visible
// ----------------------------------------------------------------------------
{
    [logoView setRendererVisible:visible];
    
//	if (!logoVisible && visible)
//	{
//        [self addSubview:logoView positioned:NSWindowAbove relativeTo:self];
//		[logoView startRendering];
//	}
//	else if (logoVisible && !visible)
//	{
//		[logoView removeFromSuperview];
//        [logoView stopRendering];
//	}
	
	logoVisible = visible;
    [self setNeedsDisplay:YES];
}


// ----------------------------------------------------------------------------
- (void)drawRect:(NSRect)rect
// ----------------------------------------------------------------------------
{
	if (!resourcesLoaded)
		[self loadResources];

	rect = self.bounds;

	// Draw background
	NSDrawThreePartImage(rect, leftBackGroundImage, middleBackGroundImage, rightBackGroundImage, NO, NSCompositingOperationSourceOver, 0.8f, NO);
	
	if (logoVisible)
		logoView.frame = self.bounds;

	if (!displayVisible)
		return;
		
	// Draw time information
	float xpos = rect.origin.x + rect.size.width - 70.0f;
	float ypos = floorf(rect.origin.y + 10.0f);
	timeDisplayFrame = NSMakeRect(xpos, ypos, 4.0f * 13.0f + 11.0f, 19.0f);

	if (showRemainingTime)
	{
		NSRect minusImageFrame = NSMakeRect(xpos - 13.0f, ypos, minusImage.size.width, minusImage.size.height);
		NSRect minusImageRect = NSMakeRect(0.0f, 0.0f, minusImage.size.width, minusImage.size.height);
        if (self.flipped)
        {
            //[minusImage setFlipped:self.flipped];
            minusImage = [minusImage flipImageVertical];
        }

		[minusImage drawInRect:minusImageFrame fromRect:minusImageRect operation:NSCompositingOperationSourceOver fraction:1.0f];
	}
	
	for (int i = 0; i < 4; i++)
	{
		NSImage* image = largeNumberImages[currentTimeDigits[i]];
		NSRect imageFrame = NSMakeRect(xpos, ypos, image.size.width, image.size.height);
		NSRect imageRect = NSMakeRect(0.0f, 0.0f, image.size.width, image.size.height);
			

        if (self.flipped)
        {
            //[image setFlipped:self.flipped];
            image = [image flipImageVertical];
        }

		[image drawInRect:imageFrame fromRect:imageRect operation:NSCompositingOperationSourceOver fraction:1.0f];
		
		xpos += image.size.width + 3.0f;
		
		if (i == 1)
		{
			imageFrame = NSMakeRect(xpos, ypos, timeDividerImage.size.width, timeDividerImage.size.height);
			imageRect = NSMakeRect(0.0f, 0.0f, timeDividerImage.size.width, timeDividerImage.size.height);
            if (self.flipped)
            {
                //[timeDividerImage setFlipped:self.flipped];
                timeDividerImage = [timeDividerImage flipImageVertical];
            }
			
			[timeDividerImage drawInRect:imageFrame fromRect:imageRect operation:NSCompositingOperationSourceOver fraction:1.0f];

			xpos += image.size.width + 1.0f;
		}
	}
	
	const float rightDisplayWidth = (chipBadge != nil && [chipBadge length] > 0) ? 180.0f : 100.0f;
	
	// Draw the title/author/release info
	NSRect tuneInfoFrame;
	if (tuneInfo != nil)
	{
		tuneInfoFrame = NSInsetRect(rect, 8.0f, 3.0f);
		tuneInfoFrame.size.width = rect.size.width - rightDisplayWidth;
		
		[tuneInfo drawInRect:tuneInfoFrame];
	}
	
	// Draw the illuminated hardware silicon chip badge
	if (chipBadge != nil && [chipBadge length] > 0)
	{
		chipBadgeFrame = NSMakeRect(rect.origin.x + rect.size.width - 165.0f, ypos + 1.0f, 88.0f, 17.0f);
		
		// 1. Ceramic DIP package body
		NSBezierPath *badgePath = [NSBezierPath bezierPathWithRoundedRect:chipBadgeFrame xRadius:3.0f yRadius:3.0f];
		[[NSColor colorWithDeviceRed:0.12f green:0.13f blue:0.16f alpha:mouseDownInChipBadge ? 0.98f : 0.88f] setFill];
		[badgePath fill];
		
		// Metallic bevel border
		[[NSColor colorWithDeviceRed:0.38f green:0.40f blue:0.46f alpha:0.75f] setStroke];
		[badgePath setLineWidth:1.0f];
		[badgePath stroke];
		
		// 2. Silver DIP dual-inline pins on top and bottom
		[[NSColor colorWithDeviceRed:0.75f green:0.77f blue:0.82f alpha:0.85f] setFill];
		for (int p = 0; p < 5; p++) {
			CGFloat pinX = chipBadgeFrame.origin.x + 16.0f + (CGFloat)p * 14.0f;
			NSRectFill(NSMakeRect(pinX, chipBadgeFrame.origin.y - 1.0f, 4.0f, 1.5f));
			NSRectFill(NSMakeRect(pinX, chipBadgeFrame.origin.y + chipBadgeFrame.size.height - 0.5f, 4.0f, 1.5f));
		}
		
		// 3. Chip pin-1 notch on left edge
		NSBezierPath *notch = [NSBezierPath bezierPath];
		[notch appendBezierPathWithArcWithCenter:NSMakePoint(chipBadgeFrame.origin.x, chipBadgeFrame.origin.y + 8.5f)
		                                 radius:2.5f
		                             startAngle:-90.0
		                               endAngle:90.0];
		[[NSColor colorWithDeviceRed:0.25f green:0.27f blue:0.30f alpha:1.0f] setFill];
		[notch fill];
		
		// 4. Status Illuminated LED dot
		NSRect ledRect = NSMakeRect(chipBadgeFrame.origin.x + 6.0f, chipBadgeFrame.origin.y + 6.0f, 5.0f, 5.0f);
		NSColor *ledColor = nil;
		if (isModTune) {
			ledColor = [NSColor colorWithDeviceRed:1.0f green:0.62f blue:0.10f alpha:1.0f]; // Amber for Paula
		} else if ([chipBadge containsString:@"8580"]) {
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
			NSFontAttributeName: [NSFont boldSystemFontOfSize:8.5f],
			NSForegroundColorAttributeName: [NSColor colorWithDeviceRed:0.92f green:0.94f blue:0.98f alpha:1.0f]
		};
		[chipBadge drawAtPoint:NSMakePoint(chipBadgeFrame.origin.x + 14.5f, chipBadgeFrame.origin.y + 2.5f) withAttributes:badgeFontAttr];
	}
	
	// Draw the subtune information
	if (subtuneInfo != nil)
	{
		float leftWidth = leftArrowImage.size.width;
		float leftHeight = leftArrowImage.size.height;
		float rightWidth = rightArrowImage.size.width;
		float rightHeight = rightArrowImage.size.height;

		subtuneInfoFrame = NSInsetRect(rect, 8.0f, 3.0f);
		subtuneInfoFrame.size.width = rightDisplayWidth;
		subtuneInfoFrame.origin.x = rect.size.width - rightDisplayWidth - 7.0f;
		subtuneInfoFrame.origin.y -= 1.0f;
		[subtuneInfo drawInRect:subtuneInfoFrame];
		
		NSRect subtuneBounds = [subtuneInfo boundingRectWithSize:subtuneInfoFrame.size options:0];
		
		xpos = rect.size.width - ceilf(NSWidth(subtuneBounds)) - 10.0f - leftWidth - rightWidth;
		ypos = floorf(rect.origin.y + 29.0f);

		leftArrowFrame = NSMakeRect(xpos, ypos, leftWidth, leftHeight);
		loopBadgeFrame = NSMakeRect(xpos - 40.0f, ypos, 36.0f, leftHeight);
		NSRect imageRect = NSMakeRect(0.0f, 0.0f, leftWidth, leftHeight);
			
		
        if (self.flipped)
        {
            //[leftArrowImage setFlipped:self.flipped];
            leftArrowImage = [leftArrowImage flipImageVertical];
        }
		[leftArrowImage drawInRect:leftArrowFrame fromRect:imageRect operation:NSCompositingOperationSourceOver fraction:mouseDownInLeftArrow ? 1.0f : 0.64f];

		xpos += leftWidth + 1.0f;

		rightArrowFrame = NSMakeRect(xpos, ypos, rightWidth, rightHeight);
		imageRect = NSMakeRect(0.0f, 0.0f, rightWidth, rightHeight);
			

        if (self.flipped)
        {
            //[rightArrowImage setFlipped:self.flipped];
            rightArrowImage = [rightArrowImage flipImageVertical];
        }
		[rightArrowImage drawInRect:rightArrowFrame fromRect:imageRect operation:NSCompositingOperationSourceOver fraction:mouseDownInRightArrow ? 1.0f : 0.64f];
	}

	if (displayVisible) {
		[self drawLoopButtonInRect:rect];
		[self drawScrubBarInRect:rect];
	}
}


/*
// ----------------------------------------------------------------------------
- (NSMenu*)menuForEvent:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	NSPoint mousePosition = [event locationInWindow];
	NSPoint mousePositionInView = [self convertPoint:mousePosition fromView:nil];

	if (displayVisible && NSPointInRect(mousePositionInView, subtuneInfoFrame))
	{
		mouseDownInSubtuneInfo = YES;
		NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
		for (int i = 0; i < 10; i++)
			[menu addItemWithTitle:[NSString stringWithFormat:@"Subtune %d", i] action:@selector(subtuneSelectedFromMenu:) keyEquivalent:@""];
		return menu;
	}

	return [[self class] defaultMenu];
}
*/


/*
// ----------------------------------------------------------------------------
- (void) updateUvMetersWithVoice1:(float)levelVoice1 andVoice2:(float)levelVoice2 andVoice3:(float)levelVoice3
// ----------------------------------------------------------------------------
{
	if (!logoVisible || !resourcesLoaded)
		return;
		
	if ([logoView superview] == nil)
		return;
		
	[logoView setValue:[NSNumber numberWithFloat:levelVoice1] forInputKey:@"protocol_Voice1_Gate"];
	[logoView setValue:[NSNumber numberWithFloat:levelVoice2] forInputKey:@"protocol_Voice2_Gate"];
	[logoView setValue:[NSNumber numberWithFloat:levelVoice3] forInputKey:@"protocol_Voice3_Gate"];
}
*/


// ----------------------------------------------------------------------------
- (void) drawScrubBarInRect:(NSRect)bounds
// ----------------------------------------------------------------------------
{
	scrubBarFrame = NSMakeRect(8.0f, 2.0f, bounds.size.width - 16.0f, 6.0f);
	
	// 1. Recessed Track
	NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:scrubBarFrame xRadius:3.0f yRadius:3.0f];
	[[NSColor colorWithCalibratedWhite:0.0f alpha:0.55f] setFill];
	[track fill];
	
	[[NSColor colorWithCalibratedWhite:0.25f alpha:0.40f] setStroke];
	[track setLineWidth:0.5f];
	[track stroke];
	
	// 2. Subtune Section Markers
	if (currentSubtuneCount > 1) {
		[[NSColor colorWithCalibratedWhite:1.0f alpha:0.40f] setFill];
		for (NSInteger s = 1; s < currentSubtuneCount; s++) {
			CGFloat markerX = scrubBarFrame.origin.x + (scrubBarFrame.size.width * (CGFloat)s) / (CGFloat)currentSubtuneCount;
			NSRectFill(NSMakeRect(markerX - 0.5f, scrubBarFrame.origin.y + 1.0f, 1.0f, scrubBarFrame.size.height - 2.0f));
		}
	}
	
	// 3. Filled Progress Bar
	double fraction = 0.0;
	if (currentSonglengthInSeconds > 0 && currentPlaybackSeconds >= 0) {
		fraction = (double)currentPlaybackSeconds / (double)currentSonglengthInSeconds;
		if (fraction > 1.0) fraction = 1.0;
	}
	
	CGFloat fillWidth = scrubBarFrame.size.width * fraction;
	if (fillWidth > 2.0f) {
		NSRect fillRect = NSMakeRect(scrubBarFrame.origin.x, scrubBarFrame.origin.y, fillWidth, scrubBarFrame.size.height);
		NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:3.0f yRadius:3.0f];
		
		SPThemeManager *tm = [SPThemeManager sharedManager];
		NSColor *accent = [tm accentColor] ?: [NSColor controlAccentColor];
		
		NSGradient *fillGradient = [[NSGradient alloc] initWithStartingColor:[accent blendedColorWithFraction:0.3f ofColor:[NSColor whiteColor]]
																 endingColor:accent];
		[fillGradient drawInBezierPath:fillPath angle:-90.0f];
	}
	
	// 4. Scrub Playhead Thumb
	CGFloat thumbX = scrubBarFrame.origin.x + fillWidth;
	CGFloat thumbRadius = (isHoveringScrubBar || isDraggingScrub) ? 5.5f : 4.0f;
	NSRect thumbRect = NSMakeRect(thumbX - thumbRadius, scrubBarFrame.origin.y + (scrubBarFrame.size.height * 0.5f) - thumbRadius, thumbRadius * 2.0f, thumbRadius * 2.0f);
	
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	[ctx saveGraphicsState];
	NSShadow *thumbGlow = [[NSShadow alloc] init];
	thumbGlow.shadowColor = [NSColor colorWithCalibratedWhite:0.0f alpha:0.45f];
	thumbGlow.shadowBlurRadius = 3.0f;
	thumbGlow.shadowOffset = NSMakeSize(0, -1.0f);
	[thumbGlow set];
	
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithOvalInRect:thumbRect] fill];
	
	[[NSColor colorWithCalibratedWhite:0.2f alpha:0.8f] setStroke];
	NSBezierPath *thumbBorder = [NSBezierPath bezierPathWithOvalInRect:thumbRect];
	[thumbBorder setLineWidth:1.0f];
	[thumbBorder stroke];
	[ctx restoreGraphicsState];
	
	// 5. Hover Time Tooltip
	if (isHoveringScrubBar && hoverScrubSeconds >= 0) {
		int elSecs = (int)hoverScrubSeconds;
		int remSecs = (int)MAX(0, currentSonglengthInSeconds - hoverScrubSeconds);
		NSString *tooltipStr = [NSString stringWithFormat:@"%02d:%02d (-%02d:%02d)", elSecs / 60, elSecs % 60, remSecs / 60, remSecs % 60];
		
		NSFont *tipFont = [NSFont monospacedDigitSystemFontOfSize:9.0f weight:NSFontWeightBold] ?: [NSFont boldSystemFontOfSize:9.0f] ?: [NSFont systemFontOfSize:9.0f];
		NSMutableDictionary *tipAttrs = [NSMutableDictionary dictionaryWithCapacity:2];
		if (tipFont) tipAttrs[NSFontAttributeName] = tipFont;
		tipAttrs[NSForegroundColorAttributeName] = [NSColor whiteColor];
		NSSize tipSize = [tooltipStr sizeWithAttributes:tipAttrs];
		CGFloat tipPadding = 4.0f;
		CGFloat tipW = tipSize.width + tipPadding * 2.0f;
		CGFloat tipH = tipSize.height + 3.0f;
		
		CGFloat tipX = hoverScrubPositionX - (tipW * 0.5f);
		if (tipX < scrubBarFrame.origin.x) tipX = scrubBarFrame.origin.x;
		if (tipX + tipW > scrubBarFrame.origin.x + scrubBarFrame.size.width) tipX = scrubBarFrame.origin.x + scrubBarFrame.size.width - tipW;
		CGFloat tipY = scrubBarFrame.origin.y + scrubBarFrame.size.height + 3.0f;
		
		NSRect tipRect = NSMakeRect(tipX, tipY, tipW, tipH);
		NSBezierPath *tipPill = [NSBezierPath bezierPathWithRoundedRect:tipRect xRadius:3.0f yRadius:3.0f];
		[[NSColor colorWithCalibratedWhite:0.10f alpha:0.92f] setFill];
		[tipPill fill];
		[[NSColor colorWithCalibratedWhite:0.40f alpha:0.65f] setStroke];
		[tipPill setLineWidth:0.75f];
		[tipPill stroke];
		
		[tooltipStr drawAtPoint:NSMakePoint(tipX + tipPadding, tipY + 1.5f) withAttributes:tipAttrs];
		
		// Vertical hover guideline
		[[NSColor colorWithCalibratedWhite:1.0f alpha:0.55f] setStroke];
		NSBezierPath *guide = [NSBezierPath bezierPath];
		[guide moveToPoint:NSMakePoint(hoverScrubPositionX, scrubBarFrame.origin.y)];
		[guide lineToPoint:NSMakePoint(hoverScrubPositionX, scrubBarFrame.origin.y + scrubBarFrame.size.height)];
		[guide setLineWidth:1.0f];
		[guide stroke];
	}
}

// ----------------------------------------------------------------------------
- (void) drawLoopButtonInRect:(NSRect)bounds
// ----------------------------------------------------------------------------
{
	BOOL repSingle = NO;
	BOOL repAll = NO;
	if ([self.window isKindOfClass:[SPPlayerWindow class]]) {
		SPPlayerWindow *win = (SPPlayerWindow *)self.window;
		repSingle = [win isRepeatSingleActive];
		repAll = [win isRepeatAllActive];
	}
	
	NSString *iconText = @"➡️";
	NSString *labelText = @"OFF";
	NSColor *btnBg = [NSColor colorWithCalibratedWhite:0.18f alpha:0.75f];
	NSColor *txtColor = [NSColor colorWithCalibratedWhite:0.75f alpha:1.0f];
	
	if (repSingle) {
		iconText = @"🔁";
		labelText = @"1";
		btnBg = [NSColor colorWithCalibratedRed:0.15f green:0.45f blue:0.85f alpha:0.85f];
		txtColor = [NSColor whiteColor];
	} else if (repAll) {
		iconText = @"🔁";
		labelText = @"ALL";
		btnBg = [NSColor colorWithCalibratedRed:0.20f green:0.65f blue:0.35f alpha:0.85f];
		txtColor = [NSColor whiteColor];
	}
	
	NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:loopBadgeFrame xRadius:3.0f yRadius:3.0f];
	[btnBg setFill];
	[pill fill];
	[[NSColor colorWithCalibratedWhite:0.5f alpha:0.5f] setStroke];
	[pill setLineWidth:0.75f];
	[pill stroke];
	
	NSString *fullStr = [NSString stringWithFormat:@"%@ %@", iconText, labelText];
	NSDictionary *attr = @{
		NSFontAttributeName: [NSFont systemFontOfSize:8.0f weight:NSFontWeightMedium],
		NSForegroundColorAttributeName: txtColor
	};
	NSSize strSize = [fullStr sizeWithAttributes:attr];
	[fullStr drawAtPoint:NSMakePoint(loopBadgeFrame.origin.x + (loopBadgeFrame.size.width - strSize.width)*0.5f,
									 loopBadgeFrame.origin.y + (loopBadgeFrame.size.height - strSize.height)*0.5f)
		  withAttributes:attr];
}

// ----------------------------------------------------------------------------
- (BOOL) acceptsFirstMouse:(NSEvent *)event
// ----------------------------------------------------------------------------
{
	return YES;
}

// ----------------------------------------------------------------------------
- (void) updateTrackingAreas
// ----------------------------------------------------------------------------
{
	[super updateTrackingAreas];
	if (scrubTrackingArea != nil) {
		[self removeTrackingArea:scrubTrackingArea];
		scrubTrackingArea = nil;
	}
	
	NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
	scrubTrackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
	[self addTrackingArea:scrubTrackingArea];
}

// ----------------------------------------------------------------------------
- (void) mouseMoved:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	if (!displayVisible || currentSonglengthInSeconds <= 0)
	{
		if (isHoveringScrubBar) {
			isHoveringScrubBar = NO;
			hoverScrubSeconds = -1;
			[self setNeedsDisplay:YES];
		}
		return;
	}
	
	NSPoint mousePosition = event.locationInWindow;
	NSPoint mousePositionInView = [self convertPoint:mousePosition fromView:nil];
	NSRect hoverTarget = NSInsetRect(scrubBarFrame, 0.0f, -6.0f);
	if (NSPointInRect(mousePositionInView, hoverTarget))
	{
		isHoveringScrubBar = YES;
		hoverScrubPositionX = mousePositionInView.x;
		CGFloat relX = mousePositionInView.x - scrubBarFrame.origin.x;
		CGFloat fraction = relX / scrubBarFrame.size.width;
		if (fraction < 0.0f) fraction = 0.0f;
		if (fraction > 1.0f) fraction = 1.0f;
		hoverScrubSeconds = (NSInteger)(fraction * currentSonglengthInSeconds);
		[self setNeedsDisplay:YES];
	}
	else if (isHoveringScrubBar)
	{
		isHoveringScrubBar = NO;
		hoverScrubSeconds = -1;
		[self setNeedsDisplay:YES];
	}
}

// ----------------------------------------------------------------------------
- (void) mouseExited:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	if (isHoveringScrubBar)
	{
		isHoveringScrubBar = NO;
		hoverScrubSeconds = -1;
		[self setNeedsDisplay:YES];
	}
}

// ----------------------------------------------------------------------------
- (void) mouseDown:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	NSPoint mousePosition = event.locationInWindow;
	NSPoint mousePositionInView = [self convertPoint:mousePosition fromView:nil];
	
	if (displayVisible && NSPointInRect(mousePositionInView, leftArrowFrame))
	{
		mouseDownInLeftArrow = YES;
		[self setNeedsDisplay:YES];
		return;
	}
	else if (displayVisible && NSPointInRect(mousePositionInView, rightArrowFrame))
	{
		mouseDownInRightArrow = YES;
		[self setNeedsDisplay:YES];
		return;
	}
	else if (displayVisible && NSPointInRect(mousePositionInView, loopBadgeFrame))
	{
		if ([self.window respondsToSelector:@selector(toggleLoopMode)]) {
			[(SPPlayerWindow*)self.window toggleLoopMode];
			[self setNeedsDisplay:YES];
			return;
		}
	}
	else if (displayVisible && currentSonglengthInSeconds > 0 && NSPointInRect(mousePositionInView, NSInsetRect(scrubBarFrame, -4.0f, -8.0f)))
	{
		isDraggingScrub = YES;
		CGFloat relX = mousePositionInView.x - scrubBarFrame.origin.x;
		CGFloat fraction = relX / scrubBarFrame.size.width;
		if (fraction < 0.0f) fraction = 0.0f;
		if (fraction > 1.0f) fraction = 1.0f;
		NSInteger targetSeconds = (NSInteger)(fraction * currentSonglengthInSeconds);
		if ([self.window respondsToSelector:@selector(seekToSeconds:)]) {
			[(SPPlayerWindow*)self.window seekToSeconds:targetSeconds];
		}
		hoverScrubPositionX = mousePositionInView.x;
		hoverScrubSeconds = targetSeconds;
		[self setNeedsDisplay:YES];
		return;
	}
	else if (displayVisible && NSPointInRect(mousePositionInView, timeDisplayFrame))
	{
		showRemainingTime = !showRemainingTime;
		[self setPlaybackSeconds:-1];
		return;
	}
	else if (displayVisible && chipBadge != nil && NSPointInRect(mousePositionInView, chipBadgeFrame))
	{
		mouseDownInChipBadge = YES;
		[self setNeedsDisplay:YES];
		return;
	}
	else
	{
		if (!inStartState)
		{
			if (logoVisible && !displayVisible)
			{
				[self setLogoVisible:NO];
				displayVisible = YES;
			}
			else if (!logoVisible && displayVisible)
			{
				[self setLogoVisible:YES];
				displayVisible = NO;
			}
		}
		
		mouseDownInLeftArrow = NO;
		mouseDownInRightArrow = NO;
		mouseDownInChipBadge = NO;
		return;
	}
	// Code will never be executed
	//[super mouseDown:event];
}

// ----------------------------------------------------------------------------
- (void) mouseDragged:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	if (isDraggingScrub && currentSonglengthInSeconds > 0)
	{
		NSPoint mousePosition = event.locationInWindow;
		NSPoint mousePositionInView = [self convertPoint:mousePosition fromView:nil];
		CGFloat relX = mousePositionInView.x - scrubBarFrame.origin.x;
		CGFloat fraction = relX / scrubBarFrame.size.width;
		if (fraction < 0.0f) fraction = 0.0f;
		if (fraction > 1.0f) fraction = 1.0f;
		NSInteger targetSeconds = (NSInteger)(fraction * currentSonglengthInSeconds);
		if ([self.window respondsToSelector:@selector(seekToSeconds:)]) {
			[(SPPlayerWindow*)self.window seekToSeconds:targetSeconds];
		}
		hoverScrubPositionX = mousePositionInView.x;
		hoverScrubSeconds = targetSeconds;
		[self setNeedsDisplay:YES];
		return;
	}
	[super mouseDragged:event];
}

// ----------------------------------------------------------------------------
- (void) mouseUp:(NSEvent*)event
// ----------------------------------------------------------------------------
{
	if (isDraggingScrub)
	{
		isDraggingScrub = NO;
		[self setNeedsDisplay:YES];
		return;
	}

	NSPoint mousePosition = event.locationInWindow;
	NSPoint mousePositionInView = [self convertPoint:mousePosition fromView:nil];
	
	if (displayVisible && NSPointInRect(mousePositionInView, leftArrowFrame) && mouseDownInLeftArrow)
	{
		mouseDownInLeftArrow = NO;
		[self setNeedsDisplay:YES];
		[(SPPlayerWindow*)self.window previousSubtune:self];
	}
	else if (displayVisible && NSPointInRect(mousePositionInView, rightArrowFrame) && mouseDownInRightArrow)
	{
		mouseDownInRightArrow = NO;
		[self setNeedsDisplay:YES];
		[(SPPlayerWindow*)self.window nextSubtune:self];
	}
	else if (displayVisible && chipBadge != nil && NSPointInRect(mousePositionInView, chipBadgeFrame) && mouseDownInChipBadge)
	{
		mouseDownInChipBadge = NO;
		[self setNeedsDisplay:YES];
		if (!isModTune) {
			if ([self.window respondsToSelector:@selector(SIDSelectorButtonPressed:)]) {
				[(SPPlayerWindow*)self.window SIDSelectorButtonPressed:self];
			}
		} else {
			NSAlert *alert = [[NSAlert alloc] init];
			alert.messageText = @"Commodore Amiga Sound Hardware";
			alert.informativeText = @"Audio Chip: MOS / CSG 8364 'Paula'\n• 4 hardware DMA sound channels (stereo left/right)\n• 8-bit linear pulse-code modulation (PCM)\n• Variable sampling rates up to 28.8 kHz (PAL) / 28.9 kHz (NTSC)\n• Native Amiga ProTracker / FastTracker / OctaMED hardware output";
			[alert runModal];
		}
	}
	else
	{
		mouseDownInLeftArrow = NO;
		mouseDownInRightArrow = NO;
		mouseDownInChipBadge = NO;
		[self setNeedsDisplay:YES];
	}
}

/*
// ----------------------------------------------------------------------------
- (void) viewWillMoveToSuperview:(NSView*)newSuperview
// ----------------------------------------------------------------------------
{
	//NSLog(@"%@: viewWillMoveToSuperview: %@\n", self, newSuperview);

	if (newSuperview == nil)
	{
		[logoView stopRendering];
		[logoView removeFromSuperview];
		logoVisible = NO;
	}

	[super viewWillMoveToSuperview:newSuperview];
}
*/

/*
// ----------------------------------------------------------------------------
- (void) viewWillMoveToWindow:(NSWindow*)newWindow
// ----------------------------------------------------------------------------
{
	//NSLog(@"%@: viewWillMoveToWindow: %@\n", self, newWindow);

	if (newWindow == nil || ![newWindow isKindOfClass:[SPPlayerWindow class]] || ![newWindow isVisible])
	{
		[logoView stopRendering];
		[logoView removeFromSuperview];
		logoVisible = NO;
	}
	else if (newWindow != nil && [newWindow isKindOfClass:[SPPlayerWindow class]])
	{
		SPPlayerWindow* window = (SPPlayerWindow*) newWindow;
		[window setStatusDisplay:self];
		
		// this is not a good idea
		[self addSubview:logoView positioned:NSWindowAbove relativeTo:self];
		[logoView startRendering];
		logoVisible = YES;
	}

	[super viewWillMoveToWindow:newWindow];
}
*/


@end
