#import "SPGradientBox.h"
#import "SPThemeManager.h"


@implementation SPGradientBox

// ----------------------------------------------------------------------------
- (void) drawRect:(NSRect)rect
// ----------------------------------------------------------------------------
{
    SPThemeManager *tm = [SPThemeManager sharedManager];
    if (tm.currentTheme == SPAppThemeSystem) {
        NSColor* startColor = [NSColor textBackgroundColor];
        NSColor* endColor = [NSColor colorWithCalibratedRed:
                             0.8f*[[startColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] redComponent]
                            green:0.8f*[[startColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] greenComponent]
                            blue:0.8f*[[startColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] blueComponent]
                            alpha:[[startColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] alphaComponent]];

        NSGradient* gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
        [gradient drawInRect:self.bounds angle:-90];
    } else {
        NSColor* startColor = [tm boxGradientStartColor];
        NSColor* endColor = [tm boxGradientEndColor];
        if (startColor && endColor) {
            NSGradient* gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
            [gradient drawInRect:self.bounds angle:-90];
        }
        NSColor* borderColor = [tm boxBorderColor];
        if (borderColor) {
            [borderColor setFill];
            NSRect lineRect = NSMakeRect(0, 0, self.bounds.size.width, 1.0f);
            NSRectFill(lineRect);
        }
    }
}

@end


@implementation SPDarkGradientBox

// ----------------------------------------------------------------------------
- (void) drawRect:(NSRect)rect
// ----------------------------------------------------------------------------
{
	NSGradient* gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.76f alpha:1.0f] endingColor:[NSColor colorWithCalibratedWhite:0.59f alpha:1.0f]];
    [gradient drawInRect:self.bounds angle:-90];

	NSColor* darkColor = [NSColor colorWithCalibratedWhite:0.3f alpha:1.0f];
	
	NSRect bounds = self.bounds;
	float ypos = bounds.origin.y + bounds.size.height;
	
	[NSBezierPath setDefaultLineWidth:1.0f];
	NSBezierPath* path = [NSBezierPath bezierPath];
	
	[path moveToPoint:NSMakePoint(rect.origin.x, ypos)];
	[path lineToPoint:NSMakePoint(rect.origin.x + rect.size.width, ypos)];
	
	[darkColor set];	
	[path stroke];
}

@end
