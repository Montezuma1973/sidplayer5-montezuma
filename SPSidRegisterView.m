#import "SPInfoContainerView.h"
#import "SPColorProvider.h"
#import "SPPlayerWindow.h"
#import "PlayerLibSidplayWrapper.h"
#import "SPSidNoteUtils.h"
#import "SPSidRegisterView.h"
#import "SPPreferencesController.h"

#pragma mark SPSidRegisterView
@implementation SPSidRegisterView

// ----------------------------------------------------------------------------
- (void) awakeFromNib
// ----------------------------------------------------------------------------
{
	[super awakeFromNib];

	index = SIDREGISTER_CONTAINER_INDEX;
	height = 133.0f;
	[self setCollapsed:gPreferences.mSidRegistersCollapsed];

	[container addInfoView:self atIndex:index];
}



@end


#pragma mark SPSidRegisterContentView
@implementation SPSidRegisterContentView


// ----------------------------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frame
// ----------------------------------------------------------------------------
{
    self = [super initWithFrame:frame];
    if (self)
	{
		player = NULL;
		registers = NULL;
	}
    return self;
}


// ----------------------------------------------------------------------------
- (void)drawRect:(NSRect)rect
// ----------------------------------------------------------------------------
{
    [super drawRect:rect];
    
	const float rowHeight = 13.0f;
	const float rowCount = 8;
	const float	columnWidth = 120.0f;

	CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
	NSArray* colors = [[SPColorProvider sharedInstance] alternatingRowBackgroundColors];
	NSColor* even = colors[1];
	NSColor* odd = colors[0];

	for (int i = 0; i < rowCount; i++)
	{
		NSRect rowRect = rect;
		rowRect.origin.y = i * rowHeight;
		rowRect.size.height = rowHeight;

		if (i & 1)
			[odd set];
		else
			[even set];
			
		//NSRectFill(rowRect);
	}
	
//	[[[SPColorProvider sharedInstance] gridColor] set];
//	[NSBezierPath strokeLineFromPoint:NSMakePoint(columnWidth - 0.5f, rect.size.height) toPoint:NSMakePoint(columnWidth - 0.5f, rect.size.height - 5.0f * rowHeight)];
//	[NSBezierPath strokeLineFromPoint:NSMakePoint(2.0f * columnWidth - 0.5f, rect.size.height) toPoint:NSMakePoint(2.0f * columnWidth - 0.5f, rect.size.height - 5.0f * rowHeight)];
	
    NSColor *strokeColor, *fillColor;
    strokeColor = [[SPColorProvider sharedInstance] rgbStrokeColor];
    fillColor = [[SPColorProvider sharedInstance] rgbFillColor];

    CGContextSetRGBStrokeColor(context,strokeColor.redComponent, strokeColor.greenComponent, strokeColor.blueComponent, strokeColor.alphaComponent);
    CGContextSetRGBFillColor(context,fillColor.redComponent, fillColor.greenComponent, fillColor.blueComponent, fillColor.alphaComponent);

    NSDictionary* stringAttributes = @{NSFontAttributeName:[NSFont fontWithName:@"Lucida Grande" size:9.0f], NSForegroundColorAttributeName:strokeColor};
    
	CGContextSetTextMatrix(context, CGAffineTransformMakeScale(1.0f, 1.0f));
	CGContextSetTextDrawingMode(context, kCGTextFill);

	if (player == NULL)
	{
		SPInfoContainerView* container = self.enclosingScrollView.documentView;
		player = (PlayerLibSidplayWrapper*) [[container ownerWindow] player];
	}
	struct SidRegisterFrame* registerFrame;
	if (player == NULL)
        return; // FIXME: better error handling
    
    registerFrame = [player getCurrentSidRegisters];

	registers = registerFrame->mRegisters;
	
	for (int i = 0; i < 3; i++)
		[self drawVoice:i intoContext:context atHorizontalPosition:rect.origin.x + columnWidth * i + 3.0f andVerticalPosition:rect.origin.y + rect.size.height - 10.0f];
		
	float xpos = rect.origin.x + 3.0f;
	float ypos = rect.origin.y + rect.size.height - 5.0f * rowHeight - 10.0f;
	char stringBuffer[256];
	
	unsigned short filterCutoff = (registers[0x15] + (registers[0x16] << 8)) >> 5;
	snprintf(stringBuffer, 255, "Filter Cutoff: $%04x", filterCutoff);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;

	int filtervoices = registers[0x17] & 0x07;
	const char* filterString = NULL;
	
	switch (filtervoices)
	{
		case 0x00:
			filterString = "(no voices are filtered)";
			break;
		case 0x01:
			filterString = "(voice 1 is filtered)";
			break;
		case 0x02:
			filterString = "(voice 2 is filtered)";
			break;
		case 0x03:
			filterString = "(voices 1+2 are filtered)";
			break;
		case 0x04:
			filterString = "(voice 3 is filtered)";
			break;
		case 0x05:
			filterString = "(voices 1+3 are filtered)";
			break;
		case 0x06:
			filterString = "(voices 2+3 are filtered)";
			break;
		case 0x07:
			filterString = "(all voices are filtered)";
			break;
	}

	snprintf(stringBuffer, 255, "Resonance/Filter: $%02x %s", registers[0x17], filterString);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;

	int filterMode = (registers[0x18] & 0x70) >> 4;
	const char* filterModeString = NULL;

	switch (filterMode)
	{
		case 0x00:
			filterModeString = "(no filter used)";
			break;
		case 0x01:
			filterModeString = "(lowpass)";
			break;
		case 0x02:
			filterModeString = "(bandpass)";
			break;
		case 0x03:
			filterModeString = "(lowpass+bandpass)";
			break;
		case 0x04:
			filterModeString = "(highpass)";
			break;
		case 0x05:
			filterModeString = "(lowpass+highpass)";
			break;
		case 0x06:
			filterModeString = "(bandpass+highpass)";
			break;
		case 0x07:
			filterModeString = "(lowpass+bandpass+highpass)";
			break;
	}

	snprintf(stringBuffer, 255, "Filtermode/Volume: $%02x %s", registers[0x18], filterModeString);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
}


// ----------------------------------------------------------------------------
- (void) drawVoice:(int)voice intoContext:(CGContextRef)context atHorizontalPosition:(float)xpos andVerticalPosition:(float)ypos
// ----------------------------------------------------------------------------
{
	const float rowHeight = 13.0f;
	int registerOffset = voice * 7;
	
	const char* voiceString = NULL;

	switch (voice)
	{
		case 0:
			voiceString = "Voice 1";
			break;
		case 1:
			voiceString = "Voice 2";
			break;
		case 2:
			voiceString = "Voice 3";
			break;
	}
    NSDictionary* stringAttributes = @{NSFontAttributeName:[NSFont fontWithName:@"Lucida Grande" size:9.0f], NSForegroundColorAttributeName:[[SPColorProvider sharedInstance] rgbStrokeColor]};

    [[NSString stringWithCString:voiceString encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;
	
	char stringBuffer[256];

	unsigned short frequency = registers[registerOffset] + (registers[registerOffset + 1] << 8);
	snprintf(stringBuffer, 255, "Frequency: $%04x", frequency);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	
	const char* noteString = SPSidNoteStringForFrequency(frequency);
    [[NSString stringWithCString:noteString encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos + 86.0f, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;

	unsigned short pulseWidth = (registers[registerOffset + 2] + (registers[registerOffset + 3 ] << 8)) & 0x0FFF;
	snprintf(stringBuffer, 255, "Pulsewidth: $%04x", pulseWidth);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;

	snprintf(stringBuffer, 255, "Waveform: $%02x", registers[registerOffset + 4]);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	ypos -= rowHeight;

	unsigned short adsr = registers[registerOffset + 6] + (registers[registerOffset + 5] << 8);
	snprintf(stringBuffer, 255, "ADSR: $%04x", adsr);
    [[NSString stringWithCString:stringBuffer encoding:NSISOLatin1StringEncoding] drawAtPoint:CGPointMake(xpos, ypos) withAttributes:stringAttributes];
	//ypos -= rowHeight;
}

@end
