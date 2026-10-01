#import "SPPlayerWindow.h"
#import "SPStatusDisplayView.h"
#import "SPPreferencesController.h"
#import "SPInfoWindowController.h"
#import "SPStilBrowserController.h"
#import "SPInfoContainerView.h"
#import "SPBrowserDataSource.h"
#import "SPExportController.h"
#import "SongLengthDatabase.h"
#import "SPCollectionUtilities.h"
#import "SPVisualizerView.h"
#import "SPApplicationStorageController.h"
#import "SPSourceListDataSource.h"
#import "SPRemixKwedOrgController.h"
#import "SPGradientBox.h"
#import "SPMiniPlayerWindow.h"
#import "SPSpectrumView.h"
#import "SPSidNoteUtils.h"
#import "SPMixerView.h"
#import "SPMenuBarPlayerController.h"

#import "PlayerLibSidplayWrapper.h"

#import <MediaPlayer/MediaPlayer.h>
#import "AudioCoreDriverNew.h"
#include <new>
#include <string.h>

NSString* SPTuneChangedNotification = @"SPTuneChangedNotification";
NSString* SPPlayerInitializedNotification = @"SPPlayerInitializedNotification";

NSString* SPUrlRequestUserAgentString = nil;
AudioCoreDriverNew* audioDriver = nil;

@interface SPPlayerWindow (VoiceMute)
- (void) toggleVoiceMute:(int)voice;
- (BOOL) isVoiceMuted:(int)voice;
@end

@interface SPVoiceNotesView : NSView
- (void) updateWithRegisters:(const uint8_t*)registers;
- (void) clearNotes;
- (void) setOwnerWindow:(SPPlayerWindow*)window;
@end

static NSString* SPInstrumentStringForControl(uint8_t control)
{
	uint8_t waveform = control & 0xF0;
	if (waveform == 0)
		return @"--";

	NSMutableArray<NSString*>* parts = [NSMutableArray arrayWithCapacity:4];
	if (waveform & 0x10) [parts addObject:@"Tri"];
	if (waveform & 0x20) [parts addObject:@"Saw"];
	if (waveform & 0x40) [parts addObject:@"Pulse"];
	if (waveform & 0x80) [parts addObject:@"Noise"];
	return [parts componentsJoinedByString:@"+"];
}

@implementation SPVoiceNotesView
{
	NSMutableArray<NSArray<NSString*>*>* noteHistory;
	NSDictionary* textAttributes;
	__weak SPPlayerWindow* ownerWindow;
	NSRect muteHitRects[8];
	NSRect soloHitRects[8];
	NSRect unmuteAllHitRect;
	NSString* lastNoteSignature;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self)
	{
		noteHistory = [NSMutableArray arrayWithCapacity:10];
		lastNoteSignature = nil;
		NSFont* font = [NSFont fontWithName:@"Menlo" size:10.0f];
		if (!font)
			font = [NSFont monospacedSystemFontOfSize:10.0f weight:NSFontWeightMedium];
		textAttributes = @{NSFontAttributeName: font,
						   NSForegroundColorAttributeName: [NSColor labelColor]};
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (void) setOwnerWindow:(SPPlayerWindow*)window
{
	ownerWindow = window;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

	NSRect bounds = self.bounds;
	if (bounds.size.width <= 0 || bounds.size.height <= 0) return;

	SPThemeManager *tm = [SPThemeManager sharedManager];
	if (tm.currentTheme == SPAppThemeSystem) {
		[[NSColor controlBackgroundColor] setFill];
	} else {
		[[tm browserBackgroundColor] setFill];
	}
	NSRectFill(dirtyRect);

	// Subtle top separator line
	NSColor *topBorderColor = [tm boxBorderColor] ?: [NSColor colorWithCalibratedWhite:0.5 alpha:0.25f];
	[topBorderColor setFill];
	NSRectFill(NSMakeRect(0, 0, bounds.size.width, 1.0f));

	NSColor* primaryColor = (tm.currentTheme == SPAppThemeSystem) ? [NSColor labelColor] : [tm browserTextColor];
	NSColor* secColor = (tm.currentTheme == SPAppThemeSystem) ? [NSColor secondaryLabelColor] : [tm browserSecondaryTextColor];
	NSColor* accentColor = [tm accentColor] ?: [NSColor controlAccentColor];

	NSFont* titleFont = [NSFont boldSystemFontOfSize:10.0f];
	NSFont* headerFont = [NSFont boldSystemFontOfSize:9.0f];
	NSFont* monoFont = [NSFont fontWithName:@"Menlo-Bold" size:10.5f] ?: [NSFont monospacedSystemFontOfSize:10.5f weight:NSFontWeightBold];
	NSFont* smallMono = [NSFont fontWithName:@"Menlo" size:8.5f] ?: [NSFont monospacedSystemFontOfSize:8.5f weight:NSFontWeightRegular];
	NSFont* buttonFont = [NSFont boldSystemFontOfSize:8.5f];

	int numChannels = ownerWindow ? [ownerWindow activeChannelCount] : 3;
	if (numChannels < 1) numChannels = 1;
	if (numChannels > 8) numChannels = 8;

	// 1. Header Bar (y: 3px to 21px)
	NSDictionary* titleAttrs = @{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: primaryColor};
	[@"VOICE & CHANNEL MATRIX" drawAtPoint:NSMakePoint(10.0f, 4.0f) withAttributes:titleAttrs];

	// Hardware Chip silicon badge in center:
	NSString* chipStr = @"MOS 6581 • 3 VOICES";
	if (ownerWindow && [ownerWindow player]) {
		if ([[ownerWindow player] isCurrentTuneMod]) {
			chipStr = [NSString stringWithFormat:@"PAULA 8364 • %d CHANNELS", numChannels];
		} else if ([[ownerWindow player] getSidChips] > 1) {
			chipStr = [NSString stringWithFormat:@"2x SID (MOS %s) • 6 VOICES", [[ownerWindow player] getCurrentChipModel]];
		} else {
			chipStr = [NSString stringWithFormat:@"MOS %s • 3 VOICES", [[ownerWindow player] getCurrentChipModel]];
		}
	}
	NSDictionary* chipAttrs = @{NSFontAttributeName: headerFont, NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.92f alpha:1.0f]};
	NSSize chipTextSize = [chipStr sizeWithAttributes:chipAttrs];
	CGFloat chipWidth = chipTextSize.width + 24.0f;
	CGFloat chipX = (bounds.size.width - chipWidth) * 0.5f;
	NSRect chipRect = NSMakeRect(chipX, 3.0f, chipWidth, 18.0f);
	NSBezierPath* chipPath = [NSBezierPath bezierPathWithRoundedRect:chipRect xRadius:3.0f yRadius:3.0f];
	[[NSColor colorWithDeviceRed:0.12f green:0.13f blue:0.16f alpha:0.92f] setFill];
	[chipPath fill];
	[[NSColor colorWithDeviceRed:0.40f green:0.42f blue:0.48f alpha:0.6f] setStroke];
	[chipPath stroke];

	// LED on chip badge
	NSColor* ledColor = [chipStr containsString:@"PAULA"] ? [NSColor colorWithDeviceRed:1.0f green:0.65f blue:0.0f alpha:1.0f] : [NSColor colorWithDeviceRed:0.2f green:0.9f blue:0.4f alpha:1.0f];
	[ledColor setFill];
	NSRect ledRect = NSMakeRect(chipX + 6.0f, 8.0f, 6.0f, 6.0f);
	[[NSBezierPath bezierPathWithOvalInRect:ledRect] fill];
	[chipStr drawAtPoint:NSMakePoint(chipX + 16.0f, 5.0f) withAttributes:chipAttrs];

	// Right: Unmute All Button
	unmuteAllHitRect = NSMakeRect(bounds.size.width - 105.0f, 3.0f, 96.0f, 18.0f);
	NSBezierPath* unmutePath = [NSBezierPath bezierPathWithRoundedRect:unmuteAllHitRect xRadius:3.0f yRadius:3.0f];
	[[NSColor colorWithCalibratedWhite:0.18f alpha:0.8f] setFill];
	[unmutePath fill];
	[[NSColor colorWithCalibratedWhite:0.5f alpha:0.3f] setStroke];
	[unmutePath stroke];
	NSMutableParagraphStyle* centerStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
	centerStyle.alignment = NSTextAlignmentCenter;
	NSDictionary* unmuteAttrs = @{NSFontAttributeName: buttonFont,
								  NSForegroundColorAttributeName: primaryColor,
								  NSParagraphStyleAttributeName: centerStyle};
	[@"UNMUTE ALL" drawInRect:NSMakeRect(unmuteAllHitRect.origin.x, 5.0f, unmuteAllHitRect.size.width, 14.0f) withAttributes:unmuteAttrs];

	// 2. Channel Matrix Cards (y: 25px, height: 68px)
	CGFloat margin = 8.0f;
	CGFloat gap = 5.0f;
	CGFloat availWidth = bounds.size.width - (margin * 2.0f);
	CGFloat cardWidth = (availWidth - ((numChannels - 1) * gap)) / (CGFloat)numChannels;
	if (cardWidth < 60.0f) cardWidth = 60.0f;

	for (int i = 0; i < numChannels; i++)
	{
		CGFloat cardX = margin + i * (cardWidth + gap);
		NSRect cardRect = NSMakeRect(cardX, 25.0f, cardWidth, 68.0f);

		// Card background
		NSBezierPath* cardPath = [NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:4.0f yRadius:4.0f];
		[[NSColor colorWithCalibratedWhite:0.0f alpha:0.22f] setFill];
		[cardPath fill];
		[[NSColor colorWithCalibratedWhite:1.0f alpha:0.10f] setStroke];
		[cardPath setLineWidth:1.0f];
		[cardPath stroke];

		BOOL isMuted = ownerWindow ? [ownerWindow isVoiceMuted:i] : NO;
		BOOL isSoloed = ownerWindow ? [ownerWindow isVoiceSoloed:i] : NO;
		float vuLevel = ownerWindow ? [ownerWindow voiceVUPeakForVoice:i] : 0.0f;
		if (isMuted) vuLevel = 0.0f;
		if (vuLevel > 1.0f) vuLevel = 1.0f;

		// Channel Title:
		NSString* chName = nil;
		if (ownerWindow && [[ownerWindow player] isCurrentTuneMod]) {
			const char* panStr = (i % 4 == 0 || i % 4 == 3) ? "L" : "R";
			chName = [NSString stringWithFormat:@"CH %d (%s)", i + 1, panStr];
		} else if (numChannels > 3) {
			int sidNum = (i < 3) ? 1 : 2;
			int vNum = (i % 3) + 1;
			chName = [NSString stringWithFormat:@"S%d-V%d", sidNum, vNum];
		} else {
			chName = [NSString stringWithFormat:@"VOICE %d", i + 1];
		}

		NSDictionary* chNameAttrs = @{NSFontAttributeName: headerFont,
									  NSForegroundColorAttributeName: isMuted ? [NSColor colorWithCalibratedRed:0.9f green:0.3f blue:0.3f alpha:1.0f] : (isSoloed ? [NSColor colorWithCalibratedRed:1.0f green:0.75f blue:0.2f alpha:1.0f] : accentColor)};
		[chName drawAtPoint:NSMakePoint(cardX + 6.0f, 28.0f) withAttributes:chNameAttrs];

		// Active Note Readout:
		NSString* noteStr = ownerWindow ? [ownerWindow channelNoteForVoice:i] : @"--";
		NSColor* noteColor = isMuted ? [NSColor disabledControlTextColor] : ([noteStr isEqualToString:@"--"] ? secColor : [NSColor colorWithCalibratedRed:0.20f green:0.85f blue:1.0f alpha:1.0f]);
		NSDictionary* noteAttrs = @{NSFontAttributeName: monoFont, NSForegroundColorAttributeName: noteColor};
		[noteStr drawAtPoint:NSMakePoint(cardX + cardWidth - 36.0f, 27.0f) withAttributes:noteAttrs];

		// Instrument / Waveform / Period:
		NSString* insStr = ownerWindow ? [ownerWindow channelInstrumentForVoice:i] : @"--";
		int period = ownerWindow ? [ownerWindow channelPeriodForVoice:i] : 0;
		NSString* subInfo = (period > 0) ? [NSString stringWithFormat:@"%@ • %d", insStr, period] : insStr;
		NSDictionary* subAttrs = @{NSFontAttributeName: smallMono, NSForegroundColorAttributeName: secColor};
		[subInfo drawAtPoint:NSMakePoint(cardX + 6.0f, 43.0f) withAttributes:subAttrs];

		// Interactive [ MUTE ] Button:
		CGFloat btnY = 58.0f;
		CGFloat btnH = 17.0f;
		CGFloat muteBtnW = 28.0f;
		CGFloat soloBtnW = 26.0f;
		muteHitRects[i] = NSMakeRect(cardX + 5.0f, btnY, muteBtnW, btnH);
		soloHitRects[i] = NSMakeRect(cardX + 35.0f, btnY, soloBtnW, btnH);

		NSBezierPath* muteBtnPath = [NSBezierPath bezierPathWithRoundedRect:muteHitRects[i] xRadius:3.0f yRadius:3.0f];
		if (isMuted) {
			[[NSColor colorWithCalibratedRed:0.85f green:0.18f blue:0.18f alpha:0.95f] setFill];
			[muteBtnPath fill];
			[[NSColor colorWithCalibratedRed:1.0f green:0.4f blue:0.4f alpha:0.8f] setStroke];
			[muteBtnPath stroke];
		} else {
			[[NSColor colorWithCalibratedWhite:0.15f alpha:0.75f] setFill];
			[muteBtnPath fill];
			[[NSColor colorWithCalibratedWhite:0.5f alpha:0.25f] setStroke];
			[muteBtnPath stroke];
		}
		NSDictionary* muteTextAttrs = @{NSFontAttributeName: buttonFont,
										NSForegroundColorAttributeName: isMuted ? [NSColor whiteColor] : secColor,
										NSParagraphStyleAttributeName: centerStyle};
		[@"M" drawInRect:NSMakeRect(muteHitRects[i].origin.x, btnY + 2.0f, muteBtnW, btnH) withAttributes:muteTextAttrs];

		// Interactive [ SOLO ] Button:
		NSBezierPath* soloBtnPath = [NSBezierPath bezierPathWithRoundedRect:soloHitRects[i] xRadius:3.0f yRadius:3.0f];
		if (isSoloed) {
			[[NSColor colorWithCalibratedRed:0.95f green:0.65f blue:0.0f alpha:0.95f] setFill];
			[soloBtnPath fill];
			[[NSColor colorWithCalibratedRed:1.0f green:0.85f blue:0.2f alpha:0.8f] setStroke];
			[soloBtnPath stroke];
		} else {
			[[NSColor colorWithCalibratedWhite:0.15f alpha:0.75f] setFill];
			[soloBtnPath fill];
			[[NSColor colorWithCalibratedWhite:0.5f alpha:0.25f] setStroke];
			[soloBtnPath stroke];
		}
		NSDictionary* soloTextAttrs = @{NSFontAttributeName: buttonFont,
										NSForegroundColorAttributeName: isSoloed ? [NSColor blackColor] : secColor,
										NSParagraphStyleAttributeName: centerStyle};
		[@"S" drawInRect:NSMakeRect(soloHitRects[i].origin.x, btnY + 2.0f, soloBtnW, btnH) withAttributes:soloTextAttrs];

		// Segmented LED VU Meter Bar:
		CGFloat vuX = cardX + 64.0f;
		CGFloat vuW = cardWidth - 69.0f;
		if (vuW > 14.0f) {
			int numSegments = (int)(vuW / 5.5f);
			if (numSegments < 4) numSegments = 4;
			if (numSegments > 10) numSegments = 10;
			CGFloat segSpacing = 1.0f;
			CGFloat segW = (vuW - (numSegments - 1) * segSpacing) / (CGFloat)numSegments;

			for (int s = 0; s < numSegments; s++) {
				CGFloat sx = vuX + s * (segW + segSpacing);
				NSRect segRect = NSMakeRect(sx, btnY + 3.0f, segW, 11.0f);
				float threshold = (float)(s + 1) / (float)numSegments;
				BOOL lit = (vuLevel >= threshold);

				NSColor* segBaseColor;
				if (s < numSegments - 3) {
					segBaseColor = [NSColor colorWithCalibratedRed:0.15f green:0.85f blue:0.35f alpha:1.0f]; // Green
				} else if (s < numSegments - 1) {
					segBaseColor = [NSColor colorWithCalibratedRed:1.0f green:0.65f blue:0.0f alpha:1.0f];  // Amber
				} else {
					segBaseColor = [NSColor colorWithCalibratedRed:1.0f green:0.20f blue:0.20f alpha:1.0f];  // Red
				}

				if (lit) {
					[segBaseColor setFill];
					NSRectFill(segRect);
				} else {
					[[segBaseColor colorWithAlphaComponent:0.15f] setFill];
					NSRectFill(segRect);
				}
			}
		}
	}

	// 3. Bottom Polyphonic Tracker Pattern Roll (y: 97px to bottom)
	CGFloat trayY = 97.0f;
	CGFloat trayH = bounds.size.height - trayY - 4.0f;
	if (trayH > 20.0f) {
		NSRect trayRect = NSMakeRect(margin, trayY, availWidth, trayH);
		NSBezierPath* trayPath = [NSBezierPath bezierPathWithRoundedRect:trayRect xRadius:3.0f yRadius:3.0f];
		[[NSColor colorWithCalibratedWhite:0.0f alpha:0.25f] setFill];
		[trayPath fill];
		[[NSColor colorWithCalibratedWhite:1.0f alpha:0.06f] setStroke];
		[trayPath stroke];

		// Draw channel column lines in tray
		for (int i = 1; i < numChannels; i++) {
			CGFloat divX = margin + i * (cardWidth + gap) - (gap * 0.5f);
			[[NSColor colorWithCalibratedWhite:1.0f alpha:0.06f] setFill];
			NSRectFill(NSMakeRect(divX, trayY, 1.0f, trayH));
		}

		// Draw scrolling pattern history rows
		CGFloat rowH = 12.0f;
		int maxRows = (int)(trayH / rowH);
		if (maxRows > 4) maxRows = 4;

		for (int r = 0; r < maxRows && r < (int)noteHistory.count; r++) {
			CGFloat ry = trayY + 2.0f + r * rowH;
			NSArray<NSString*>* rowNotes = noteHistory[r];
			float rowAlpha = 1.0f - ((float)r * 0.22f);
			if (rowAlpha < 0.25f) rowAlpha = 0.25f;

			for (int ch = 0; ch < numChannels && ch < (int)rowNotes.count; ch++) {
				CGFloat chX = margin + ch * (cardWidth + gap) + 6.0f;
				NSString* n = rowNotes[ch];
				NSColor* c = [n isEqualToString:@"--"] ? [secColor colorWithAlphaComponent:rowAlpha * 0.6f] : [primaryColor colorWithAlphaComponent:rowAlpha];
				NSDictionary* histAttrs = @{NSFontAttributeName: smallMono, NSForegroundColorAttributeName: c};
				[n drawAtPoint:NSMakePoint(chX, ry) withAttributes:histAttrs];
			}
		}
	}
}

- (void) mouseDown:(NSEvent*)event
{
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

	if (NSPointInRect(point, unmuteAllHitRect))
	{
		if (ownerWindow) [ownerWindow unmuteAllVoices];
		[self setNeedsDisplay:YES];
		return;
	}

	int numChannels = ownerWindow ? [ownerWindow activeChannelCount] : 3;
	if (numChannels > 8) numChannels = 8;

	for (int i = 0; i < numChannels; i++)
	{
		if (NSPointInRect(point, muteHitRects[i]))
		{
			if (ownerWindow)
				[ownerWindow toggleVoiceMute:i];
			[self setNeedsDisplay:YES];
			return;
		}
		if (NSPointInRect(point, soloHitRects[i]))
		{
			if (ownerWindow)
				[ownerWindow toggleVoiceSolo:i];
			[self setNeedsDisplay:YES];
			return;
		}
	}
	[super mouseDown:event];
}

- (void) updateWithRegisters:(const uint8_t*)registers
{
	if (!ownerWindow)
		return;

	int numChannels = [ownerWindow activeChannelCount];
	if (numChannels < 1) numChannels = 1;
	if (numChannels > 8) numChannels = 8;

	NSMutableArray<NSString*>* currentNotes = [NSMutableArray arrayWithCapacity:numChannels];
	NSMutableString* sig = [NSMutableString string];
	for (int i = 0; i < numChannels; i++) {
		NSString* n = [ownerWindow channelNoteForVoice:i] ?: @"--";
		NSString* ins = [ownerWindow channelInstrumentForVoice:i] ?: @"--";
		NSString* cell = [NSString stringWithFormat:@"%@ %@", n, ins];
		[currentNotes addObject:cell];
		[sig appendFormat:@"%@|", cell];
	}

	if (!lastNoteSignature || ![lastNoteSignature isEqualToString:sig]) {
		lastNoteSignature = sig;
		[noteHistory insertObject:currentNotes atIndex:0];
		if (noteHistory.count > 10) {
			[noteHistory removeLastObject];
		}
	}

	[self setNeedsDisplay:YES];
}

- (void) clearNotes
{
	[noteHistory removeAllObjects];
	lastNoteSignature = nil;
	[self setNeedsDisplay:YES];
}

@end

@implementation SPPlayerWindow

// ----------------------------------------------------------------------------
- (void) awakeFromNib
{
    [[SPPreferencesController sharedInstance] load];
    [remixKwedOrgController acquireDatabase];
    [remixKwedOrgController setOwnerWindow:self];
	if (voiceNotesView != nil)
		[voiceNotesView setOwnerWindow:self];
	if (spectrumView != nil)
		[spectrumView setOwnerWindow:self];
    
    if (gPreferences.mInfoWindowVisible)
    {
        infoWindowController = [[SPInfoWindowController alloc] init];
        [infoWindowController setOwnerWindow:self];
    }
    else
        infoWindowController = nil;
    
    stilBrowserController = nil;
    prefsWindowController = nil;
    
    player = [[PlayerLibSidplayWrapper alloc] init];
    audioDriver = new (std::nothrow) AudioCoreDriverNew;
    if (audioDriver == nil)
        return;
    
    [player setAudioDriver:(void*)audioDriver];
    
    audioDriver->initialize(player);
    audioDriver->setVolume(gPreferences.mPlaybackVolume);
    struct PlaybackSettings dummySettings;
    [gPreferences getPlaybackSettings:&dummySettings];
    dummySettings.mFrequency = audioDriver->getSampleRate();
    [gPreferences copyPlaybackSettings:&dummySettings];
    
    /* FIXME: Filter settings (again)
     sid_filter_t filterSettings;
     PlayerLibSidplay::setFilterSettingsFromPlaybackSettings(filterSettings, &gPreferences.mPlaybackSettings);
     player->setFilterSettings(&filterSettings);
     */
    [[NSNotificationCenter defaultCenter] postNotificationName:SPPlayerInitializedNotification object:self];
    
    [self setupRemoteCommandCenter];
    
    volumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    miniVolumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    volumeIsMuted = NO;
    fadeOutInProgress = NO;
    fadeOutVolume = 1.0f;
    
    currentTunePath = nil;
    currentTuneLengthInSeconds = 0;
    
    urlDownloadData = nil;
    urlDownloadConnection = nil;
    
    lastBufferUnderrunCheckReset = nil;
    
    [exportController setOwnerWindow:self];
    
    showPlayButton = YES;
    //disable Update item for now
    //[checkForUpdatesMenuItem setEnabled:FALSE];
    
    [self populateVisualizerMenu];
    //FIXME: Beta designation!
    //[self setTitle:@"SIDPLAY 5.1 BETA 4 (libsidfp/reSID/SIDBlaster USB)"];
    [self setTitle:@"SIDPLAY"];
    
    visualizerView = nil;
    /*
     visualizerView = [[SPVisualizerView alloc] init];
     [visualizerView setFrame:[self frame]];
     [visualizerView setEraseColor:[NSColor colorWithDeviceRed:0.0f green:0.0f blue:0.0f alpha:1.0f]];
     NSString* visualizerPath = [NSString stringWithFormat:@"%@%@",[[NSBundle mainBundle] resourcePath],@"/DefaultVisualizer.qtz"];
     [visualizerView loadCompositionFromFile:visualizerPath];
     [visualizerView setAutostartsRendering:YES];
     [visualizerView setAutoresizesSubviews:YES];
     [visualizerView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
     */
    
    NSDictionary* infoDictionary = [NSBundle mainBundle].infoDictionary;
    NSString* appNameString = infoDictionary[@"CFBundleName"];
    NSString* appVersionString = infoDictionary[@"CFBundleVersion"];
    NSString* osVersionString = [NSProcessInfo processInfo].operatingSystemVersionString;
    SPUrlRequestUserAgentString = [NSString stringWithFormat:@"%@/%@ (Mac OS X, %@)", appNameString, appVersionString, osVersionString];
    
    
    NSString* key = [NSString stringWithFormat:@"NSSplitView Subview Frames %@", splitView.autosaveName];
    NSArray* subviewFrames = [[NSUserDefaults standardUserDefaults] valueForKey:key];
    
    if (subviewFrames.count > 0)
    {
        // the last frame is skipped because I have one less divider than I have frames
        for (NSInteger i=0; i < (subviewFrames.count - 1); i++ )
        {
            // this is the saved frame data - it's an NSString
            NSString* frameString = subviewFrames[i];
            NSArray* components = [frameString componentsSeparatedByString:@", "];
            
            // only one component from the string is needed to set the position
            CGFloat position;
            
            if (splitView.vertical)
                position = [components[2] floatValue];
            else
                position = [components[3] floatValue];
            
            [splitView setPosition:position ofDividerAtIndex:i];
        }
    }

    [rightView setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rightViewFrameDidChange:) name:NSViewFrameDidChangeNotification object:rightView];
    [self layoutVoiceNotesView];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutVoiceNotesView];
    });

    [self setupSidebarVisualEffectView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChangeNotification:) name:SPThemeDidChangeNotification object:nil];
    [self setupThemeMenu];
    [self applyCurrentTheme];
}

// ----------------------------------------------------------------------------
- (void) rightViewFrameDidChange:(NSNotification*)notification
// ----------------------------------------------------------------------------
{
    [self layoutVoiceNotesView];
}

// ----------------------------------------------------------------------------
- (void) layoutVoiceNotesView
// ----------------------------------------------------------------------------
{
    if (!voiceNotesView || !browserScrollView || !rightView || !boxView)
        return;

    NSView* rightViewAsView = (NSView*)rightView;
    const CGFloat desiredNotesHeight = 150.0f;
    NSRect rightBounds = rightViewAsView.bounds;
    CGFloat topBoxHeight = boxView.frame.size.height;
    CGFloat availableHeight = rightBounds.size.height - topBoxHeight;
    if (availableHeight <= 0.0f)
        return;

    CGFloat notesHeight = MIN(desiredNotesHeight, MAX(0.0f, availableHeight - 80.0f));
    NSRect notesFrame = NSMakeRect(0.0f, 0.0f, rightBounds.size.width, notesHeight);
    voiceNotesView.frame = notesFrame;

    NSRect browserFrame = NSMakeRect(0.0f, notesHeight, rightBounds.size.width, availableHeight - notesHeight);
    browserScrollView.frame = browserFrame;
    browserScrollView.hidden = NO;
    browserScrollView.alphaValue = 1.0f;
    voiceNotesView.hidden = NO;

    if (browserScrollView.superview == rightViewAsView && voiceNotesView.superview == rightViewAsView)
    {
        [rightViewAsView addSubview:browserScrollView positioned:NSWindowAbove relativeTo:voiceNotesView];
        [rightViewAsView addSubview:voiceNotesView positioned:NSWindowBelow relativeTo:browserScrollView];
    }

    NSView* documentView = browserScrollView.documentView;
    if (documentView)
    {
        documentView.frame = browserScrollView.contentView.bounds;
        [documentView setNeedsDisplay:YES];
    }
    [browserScrollView setNeedsDisplay:YES];
    NSLog(@"VoiceNotes layout - right: %@ browser: %@ notes: %@",
          NSStringFromRect(rightBounds),
          NSStringFromRect(browserScrollView.frame),
          NSStringFromRect(voiceNotesView.frame));
}

// ----------------------------------------------------------------------------
- (void)setupRemoteCommandCenter {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

    // Enable commands
    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.togglePlayPauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;

    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self clickPlayPauseButton:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self clickPlayPauseButton:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self clickPlayPauseButton:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self nextSubtune:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self previousSubtune:nil];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    // To register in Now Playing, we have to set to 'Playing' once – but we're actually stopped.
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStatePlaying;
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStateStopped;
}

// ----------------------------------------------------------------------------
- (void) playTuneAtPath:(NSString*)path
{
    [self playTuneAtPath:path subtune:0];
}

// ----------------------------------------------------------------------------
- (void) playTuneAtPath:(NSString*)path subtune:(int)subtuneIndex
{
    struct PlaybackSettings dummySettings;
    [gPreferences getPlaybackSettings:&dummySettings];
    dummySettings.mFrequency = audioDriver->getSampleRate();
    [gPreferences copyPlaybackSettings:&dummySettings];
    
    bool success = [player playTuneByPath:[path cStringUsingEncoding:NSUTF8StringEncoding]
                                  subtune:subtuneIndex
                             withSettings:&dummySettings];
    if (success)
    {
        if (voiceNotesView != nil)
            [voiceNotesView clearNotes];
        if (fadeOutInProgress)
            [self stopFadeOut];
        
        currentTunePath = path;
        
        [self updateTuneInfo];
        [self setPlayPauseButtonToPause:YES];
    }
}

// ----------------------------------------------------------------------------
- (void) playTuneAtURL:(NSString*)urlString
{
    [self playTuneAtURL:urlString subtune:0];
}

// ----------------------------------------------------------------------------
- (void) playTuneAtURL:(NSString*)urlString subtune:(int)subtuneIndex
{
    while (urlDownloadConnection != nil)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1f]];
    
    urlDownloadSubtuneIndex = subtuneIndex;
    urlDownloadData = [NSMutableData data];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60.0];
    [request setValue:SPUrlRequestUserAgentString forHTTPHeaderField:@"User-Agent"];
    
    // moved from NSURLConnection to NSURLSession, according to
    // https://www.objc.io/issues/5-ios7/from-nsurlconnection-to-nsurlsession/
    NSURLSession* databaseDownloadSession = [NSURLSession sharedSession];
    NSURLSessionDataTask *dwnTask = [databaseDownloadSession dataTaskWithRequest:request
                                                               completionHandler:
                                     ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error: %@", error.localizedDescription);
			dispatch_async(dispatch_get_main_queue(), ^{
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setMessageText:@"Download failed"];
				[alert setInformativeText:error.localizedDescription];
				[alert setAlertStyle:NSAlertStyleInformational];
				[alert addButtonWithTitle:@"OK"];

				[alert runModal];
			});
        } else {
            [self->urlDownloadData appendData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self connectionDidFinishLoading];
            });
        }
    }];
    
    [dwnTask resume];
    
}

// ----------------------------------------------------------------------------
- (void)connectionDidFinishLoading
// ----------------------------------------------------------------------------
{
    struct PlaybackSettings dummySettings;
    [gPreferences getPlaybackSettings:&dummySettings];
    bool success = [player playTuneFromBuffer:(char*)urlDownloadData.bytes
                                   withLength:(int)urlDownloadData.length
                                      subtune: (int)urlDownloadSubtuneIndex
                                 withSettings:&dummySettings];
    if (success)
    {
        if (voiceNotesView != nil)
            [voiceNotesView clearNotes];
        currentTunePath = nil;
        [self setFadeVolume:1.0f];
        [self setPlayPauseButtonToPause:YES];
        [self updateTuneInfo];
    }
    else
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Invalid URL"];
        [alert setInformativeText:@"The URL did not contain a valid SID file."];
        [alert setAlertStyle:NSAlertStyleInformational]; // or NSAlertStyleWarning, or NSAlertStyleCritical
        [alert addButtonWithTitle:@"OK"];
        
        [alert runModal];
    }
    
    urlDownloadData = nil;
    urlDownloadConnection = nil;
}

// ----------------------------------------------------------------------------
- (void) setPlayPauseButtonToPause:(BOOL)pause
{
    if (pause)
    {
        playPauseButton.image = [NSImage imageNamed:@"SIDhud_pause.pause"];
        //[playPauseButton setAlternateImage:[NSImage imageNamed:@"pause_pressed"]];
        
        miniPlayPauseButton.image = [NSImage imageNamed:@"SIDhud_pause.pause"];
        //[miniPlayPauseButton setAlternateImage:[NSImage imageNamed:@"pause_pressed"]];

        [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStatePlaying;
        showPlayButton = false;
        [[SPMenuBarPlayerController sharedController] updatePlaybackState:YES];
    }
    else
    {
        playPauseButton.image = [NSImage imageNamed:@"SIDhud_play.play"];
        //[playPauseButton setAlternateImage:[NSImage imageNamed:@"play_pressed"]];
        
        miniPlayPauseButton.image = [NSImage imageNamed:@"SIDhud_play.play"];
        //[miniPlayPauseButton setAlternateImage:[NSImage imageNamed:@"play_pressed"]];

        [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStatePaused;
        showPlayButton = true;
        [[SPMenuBarPlayerController sharedController] updatePlaybackState:NO];
    }
}

// ----------------------------------------------------------------------------
- (void) switchToSubtune:(NSInteger)subtune
{
    if (fadeOutInProgress)
        [self stopFadeOut];
    [player startSubtune:(int)subtune];
    [self updateTuneInfo];
}

// ----------------------------------------------------------------------------
- (void) keyDown:(NSEvent*)event
{
    NSString* characters = event.charactersIgnoringModifiers;
    unichar character = [characters characterAtIndex:0];
    
    switch(character)
    {
        case ' ':
            [self clickPlayPauseButton:self];
            break;
        case 't':
        case 'T':
        {
            id resp = [self firstResponder];
            if (![resp isKindOfClass:[NSText class]]) {
                [self cycleThemeFromMenu:self];
                return;
            }
            [super keyDown:event];
            break;
        }
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        {
            id resp = [self firstResponder];
            if (![resp isKindOfClass:[NSText class]]) {
                int ch = (int)(character - '1');
                if (ch < [self activeChannelCount]) {
                    if ((event.modifierFlags & NSEventModifierFlagOption) || (event.modifierFlags & NSEventModifierFlagShift)) {
                        [self toggleVoiceSolo:ch];
                    } else {
                        [self toggleVoiceMute:ch];
                    }
                    return;
                }
            }
            [super keyDown:event];
            break;
        }
        case '0':
        case 'u':
        case 'U':
        {
            id resp = [self firstResponder];
            if (![resp isKindOfClass:[NSText class]]) {
                [self unmuteAllVoices];
                return;
            }
            [super keyDown:event];
            break;
        }
        default:
            [super keyDown:event];
    }
}

// ----------------------------------------------------------------------------
- (void) keyUp:(NSEvent*)event
{
    NSString* characters = event.charactersIgnoringModifiers;
    unichar character = [characters characterAtIndex:0];
    
    switch(character)
    {
        case ' ':
            break;
        default:
            [super keyUp:event];
    }
}

// ----------------------------------------------------------------------------
- (void) updateTimer
{
    NSInteger seconds = player != NULL ? (NSInteger)[player getPlaybackSeconds] : 0;
    [statusDisplay setPlaybackSeconds:seconds];
    [miniStatusDisplay setPlaybackSeconds:seconds];
    [browserDataSource updateCurrentSong:seconds];

    // update sidPopup state and tooltip
    if ([player isUsbDeviceActive]) {
        [sidPopup setEnabled:FALSE];
        [sidPopup setToolTip:@"USB SID device active"];
    } else if ([player isCurrentTuneMod]) {
        [sidPopup setEnabled:TRUE];
        [sidPopup setToolTip:@"Amiga MOS / CSG 8364 'Paula' (4-Channel 8-bit PCM Hardware DMA)"];
    } else {
        [sidPopup setEnabled:TRUE];
        const char *rawChip = [player getCurrentChipModel];
        NSString *chipStr = (rawChip && strlen(rawChip) > 0) ? [NSString stringWithUTF8String:rawChip] : @"MOS 6581";
        [sidPopup setToolTip:[NSString stringWithFormat:@"SID Chip: %@ (Click to configure SID model/filters)", chipStr]];
    }
    [sidPopup setNeedsDisplay:TRUE];
    [sidPopup.superview displayIfNeeded];
    
    // update elapsed time for media controls
    NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
    if (nowPlayingInfo) {
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(seconds);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    }
    
    if (player != NULL && [NSRunLoop currentRunLoop].currentMode != NSEventTrackingRunLoopMode)
    {
        int defaultTempo = 50;
        if ([player getTempo] != defaultTempo)
        {
            [player setTempo:defaultTempo];
            tempoSlider.integerValue = defaultTempo;
        }
    }
    
    static int updatesWithNoBufferUnderrun = 0;
    
    if (audioDriver != NULL)
    {
        if (audioDriver->getBufferUnderrunDetected())
        {
            updatesWithNoBufferUnderrun = 0;
            [player stopPlayback];
            audioDriver->setBufferUnderrunDetected(false);
            [self setPlayPauseButtonToPause:NO];
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Your Mac is too slow to play at the current emulation accuracy"];
            [alert setInformativeText:@"Please lower the emulation accuracy or turn off filter distortion in the playback preferences."];
            [alert setAlertStyle:NSAlertStyleInformational]; // or NSAlertStyleWarning, or NSAlertStyleCritical
            [alert addButtonWithTitle:@"OK"];
            
            [alert runModal];
        }
        else
        {
            updatesWithNoBufferUnderrun++;
            if (updatesWithNoBufferUnderrun >= 100)
            {
                audioDriver->setBufferUnderrunDetected(false);
                updatesWithNoBufferUnderrun = 0;
            }
        }
    }
}

// ----------------------------------------------------------------------------
- (void) updateFastTimer
{
    if (infoWindowController != nil)
        [[infoWindowController containerView] updateAnimatedViews];
    if ([player usbError]) {
        // in case of USB issues stop
        [self clickStopButton:self];
        [player releaseUSBDevices];
        // restart everything.
        player = [[PlayerLibSidplayWrapper alloc] init];
        audioDriver->initialize(player);
        [player setAudioDriver:audioDriver];
        return;
    }
    
    if (fadeOutInProgress)
    {
        fadeOutVolume -= 0.006f;
        if (fadeOutVolume < 0.0f)
            fadeOutVolume = 0.0f;
        
        [self setFadeVolume:fadeOutVolume];
    }
    // update big scope view
    if (oscillosscopeWindowController)
    {
        [oscillosscopeWindowController updateScope];
    }
    BOOL isOptionPressed = NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption ? YES : NO;
    if (isOptionPressed)
    {
        [addPlaylistButton setHidden:YES];
        [addSmartPlaylistButton setHidden:NO];
    }
    else
    {
        [addPlaylistButton setHidden:NO];
        [addSmartPlaylistButton setHidden:YES];
    }
    
    if (player != NULL)
    {
        struct SidRegisterFrame *registerFrame = [player getCurrentSidRegisters];
        unsigned char* registers = registerFrame->mRegisters;
        
        //TODO: where is that used?
        // if (audioDriver->getIsPlaying())
        //{
            /*
            float levelVoice1 = (registers[0x04] & 0x01) ? float(registers[0x06] >> 4) / 15.0f : 0.0f;
            float levelVoice2 = (registers[0x0b] & 0x01) ? float(registers[0x0d] >> 4) / 15.0f : 0.0f;
            float levelVoice3 = (registers[0x12] & 0x01) ? float(registers[0x14] >> 4) / 15.0f : 0.0f;
            */
            /*
             if ([statusDisplay logoVisible])
             [statusDisplay updateUvMetersWithVoice1:levelVoice1 andVoice2:levelVoice2 andVoice3:levelVoice3];
             
             if ([miniStatusDisplay logoVisible])
             [miniStatusDisplay updateUvMetersWithVoice1:levelVoice1 andVoice2:levelVoice2 andVoice3:levelVoice3];
             }
             else
             {
             if ([statusDisplay logoVisible])
             [statusDisplay updateUvMetersWithVoice1:0.0f andVoice2:0.0f andVoice3:0.0f];
             
             if ([miniStatusDisplay logoVisible])
             [miniStatusDisplay updateUvMetersWithVoice1:0.0f andVoice2:0.0f andVoice3:0.0f];
             }
             */
        //}
        if (voiceNotesView != nil)
            [voiceNotesView updateWithRegisters:registers];

        if (visualizerView != nil && visualizerView.superview != nil)
        {
            VisualizerState state;
            
            int voiceRamOffset[3] = {0, 7, 14};
            
            for (int i = 0; i < 3; i++)
            {
                int ramoffset = voiceRamOffset[i];
                
                state.voice[i].Gatebit = registers[ ramoffset + 4 ] & 1;
                state.voice[i].Frequency = registers[ ramoffset ] + ( registers[ ramoffset + 1 ] << 8 );
                state.voice[i].Pulsewidth = ( registers[ ramoffset + 2 ] + ( registers[ ramoffset + 3 ] << 8 ) ) & 0x0FFF;
                state.voice[i].Waveform = registers[ ramoffset + 4 ] & 0xfe;
                state.voice[i].Attack = registers[ ramoffset + 5 ] >> 4;
                state.voice[i].Decay = registers[ ramoffset + 5 ] & 0x0f;
                state.voice[i].Sustain = registers[ ramoffset + 6 ] >> 4;
                state.voice[i].Release = registers[ ramoffset + 6 ] & 0x0f;
            }
            
            state.FilterCutoff = ( registers[ 0x15 ] + ( registers[ 0x16 ] << 8 ) ) >> 5;
            state.FilterResonance = registers[ 0x17 ] >> 4;
            state.FilterVoices = registers[ 0x17 ] & 0x07;
            state.FilterMode = registers[ 0x18 ] >> 4;
            state.Volume = registers[ 0x18 ] & 0x0f;
            
            [visualizerView update:&state];
        }
    }

    if (spectrumView != nil && audioDriver != NULL)
    {
        static const int kSpectrumSampleCount = 1024;
        short samples[kSpectrumSampleCount];
        int sampleRate = audioDriver->getSampleRate();
        BOOL isPlaying = audioDriver->getIsPlaying();
        if (isPlaying)
        {
            int copied = audioDriver->copySpectrumSamples(samples, kSpectrumSampleCount);
            if (copied > 0)
                [spectrumView updateWithSamples:samples count:copied sampleRate:sampleRate];
        }
        else
        {
            memset(samples, 0, sizeof(samples));
            [spectrumView updateWithSamples:samples count:kSpectrumSampleCount sampleRate:sampleRate];
        }

        BOOL isMod = (player != nil) ? [player isCurrentTuneMod] : NO;
        NSTimeInterval playTime = (player != nil) ? (NSTimeInterval)[player getPlaybackSeconds] : 0;
        NSTimeInterval totalTime = (player != nil) ? (NSTimeInterval)[player getTotalTime] : 0;
        NSString *title = nil;
        if (player != nil && [player hasTuneInformationStrings]) {
            const char *rawTitle = [player getCurrentTitle];
            if (rawTitle && strlen(rawTitle) > 0) {
                title = [NSString stringWithUTF8String:rawTitle];
            }
        }
        NSString* chipName = @"MOS 6581";
        if (isMod) {
            chipName = @"PAULA 8364";
        } else if (player != nil) {
            const char* rawChip = [player getCurrentChipModel];
            if (rawChip && strlen(rawChip) > 0) {
                chipName = [NSString stringWithUTF8String:rawChip];
            }
            if ([player getSidChips] > 1) {
                chipName = [NSString stringWithFormat:@"2x %@", chipName];
            }
        }

        [spectrumView updatePlaybackState:isPlaying
                                    isMod:isMod
                                 playTime:playTime
                                totalTime:totalTime
                                tuneTitle:title
                                chipModel:chipName];

        [[SPMenuBarPlayerController sharedController] updatePlaybackTime:playTime
                                                               totalTime:totalTime
                                                               isPlaying:isPlaying];
    }
}

// ----------------------------------------------------------------------------
- (void) updateSlowTimer
{
    //[sourceListDataSource checkForRemoteUpdateRevisionChange];
}

// ----------------------------------------------------------------------------
- (void) updateTuneInfo
{
    if (player == NULL)
        return;
    
    NSString* title = @"No information available";
    NSString* author = @"";
    NSString* releaseInfo = @"";
    
    if ([player hasTuneInformationStrings])
    {
        title = [NSString stringWithCString:[player getCurrentTitle] encoding:NSISOLatin1StringEncoding];
        author = [NSString stringWithCString:[player getCurrentAuthor] encoding:NSISOLatin1StringEncoding];
        releaseInfo = [NSString stringWithCString:[player getCurrentReleaseInfo] encoding:NSISOLatin1StringEncoding];
    }
    
    int currentSubtune = [player getCurrentSubtune];
    int subtuneCount = [player getSubtuneCount];
    
    int tuneLength = 0;
    char* tuneBuffer = [player getTuneBuffer:&tuneLength];
    
    //char* tuneBuffer = NULL;
    if ([player isCurrentTuneMod]) {
        currentTuneLengthInSeconds = [player getTotalTime];
        if (currentTuneLengthInSeconds <= 0) {
            currentTuneLengthInSeconds = (gPreferences && gPreferences.mDefaultPlayTime > 0) ? gPreferences.mDefaultPlayTime : 180;
        }
    } else {
        currentTuneLengthInSeconds = tuneBuffer == NULL ? 0 : [[SongLengthDatabase sharedInstance] getSongLengthFromBuffer:tuneBuffer withBufferLength:tuneLength andSubtune:currentSubtune];
        if (currentTuneLengthInSeconds <= 0) {
            currentTuneLengthInSeconds = (gPreferences && gPreferences.mDefaultPlayTime > 0) ? gPreferences.mDefaultPlayTime : 180;
        }
    }
    
    NSString* chipName = @"MOS 6581";
    if ([player isCurrentTuneMod]) {
        chipName = @"PAULA 8364";
    } else {
        const char* rawChip = [player getCurrentChipModel];
        if (rawChip && strlen(rawChip) > 0) {
            chipName = [NSString stringWithUTF8String:rawChip];
        }
        if ([player getSidChips] > 1) {
            chipName = [NSString stringWithFormat:@"2x %@", chipName];
        }
    }
    
    [statusDisplay setTitle:title andAuthor:author andReleaseInfo:releaseInfo andSubtune:currentSubtune ofSubtunes:subtuneCount withSonglength:(int)currentTuneLengthInSeconds];
    [statusDisplay setChipBadge:chipName isMod:[player isCurrentTuneMod]];
    [miniStatusDisplay setTitle:title andAuthor:author andReleaseInfo:releaseInfo andSubtune:currentSubtune ofSubtunes:subtuneCount withSonglength:(int)currentTuneLengthInSeconds];
    [miniStatusDisplay setChipBadge:chipName isMod:[player isCurrentTuneMod]];
    
    [[SPMenuBarPlayerController sharedController] updateTuneTitle:title
                                                           author:author
                                                      releaseInfo:releaseInfo
                                                          subtune:currentSubtune
                                                     subtuneCount:subtuneCount
                                                           length:(int)currentTuneLengthInSeconds
                                                             chip:chipName
                                                            isMod:[player isCurrentTuneMod]];
    
    [[SPPreferencesController sharedInstance] initializeFilterSettingsFromChipModelOfPlayer:player];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
    
    // update dock tile menu
    NSMenuItem* titleItem = [dockTileMenu itemWithTag:2];
    NSMenuItem* authorItem = [dockTileMenu itemWithTag:3];
    titleItem.title = [NSString stringWithFormat:@"   %@ (%d/%d)", title, currentSubtune, subtuneCount];
    authorItem.title = [NSString stringWithFormat:@"   %@", author];
    
    NSArray* menuItems = [subtuneSelectionMenu.itemArray copy];
    for (NSMenuItem* menuItem in menuItems)
        [subtuneSelectionMenu removeItem:menuItem];
    
    for (int i = 1; i < (subtuneCount + 1); i++)
    {
        NSString* subtuneString = [NSString stringWithFormat:@"%d", i];
        NSString* keyEquivalent = nil;
        if (i < 10)
            keyEquivalent = subtuneString;
        else if (i == 10)
            keyEquivalent = @"0";
        else
            keyEquivalent = @"";
        
        NSMenuItem* item = [subtuneSelectionMenu addItemWithTitle:subtuneString action:@selector(selectSubtune:) keyEquivalent:keyEquivalent];
        item.target = self;
        item.tag = i;
    }
    
    // update Now Playing Info for media controls
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    nowPlayingInfo[MPMediaItemPropertyTitle] = title;
    nowPlayingInfo[MPMediaItemPropertyArtist] = author;
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(currentTuneLengthInSeconds);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @([player getPlaybackSeconds]);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
}
#pragma mark Audio Driver helper functions
- (BOOL) audioDriverIsAvailable
{
    if (audioDriver != nil)
        return YES;
    else
        return NO;
}
- (void) audioDriverStartPlaying
{
    [player startPlayback];
}
- (void) audioDriverStopPlaying
{
    [player stopPlayback];
}
- (short*) audioDriverSampleBuffer
{
    if (audioDriver != NULL)
        return audioDriver->getSampleBuffer();
    return NULL;
}
- (const short*) voiceScopeBufferForVoice:(int) voice
{
    if (player == NULL)
        return NULL;
    return [player voiceScopeBufferForVoice:voice];
}
- (unsigned int) voiceScopeBufferSize
{
    if (player == NULL)
        return 0;
    return [player voiceScopeBufferSize];
}
- (unsigned int) voiceScopeWriteIndex
{
    if (player == NULL)
        return 0;
    return [player voiceScopeWriteIndex];
}
- (BOOL) audioDriverIsPlaying
{
    if (audioDriver != NULL)
        return audioDriver->getIsPlaying();
    return NO;
}
/*
// ----------------------------------------------------------------------------
- (AudioDriver*) audioDriver
{
    return audioDriver;
}
*/
// ----------------------------------------------------------------------------
- (PlayerLibSidplayWrapper*) player;
{
    return player;
}

// ----------------------------------------------------------------------------
- (int) activeChannelCount
{
	if (player == NULL)
		return 3;
	return [player activeChannelCount];
}

// ----------------------------------------------------------------------------
- (BOOL) isVoiceMuted:(int)voice
{
	if (player == NULL)
		return NO;
	return [player isVoiceMuted:voice];
}

// ----------------------------------------------------------------------------
- (void) toggleVoiceMute:(int)voice
{
	if (player == NULL)
		return;

	[player toggleVoiceMuted:voice];

	if (infoWindowController != nil)
	{
		SPMixerView* mixerView = [[infoWindowController containerView] mixerView];
		if (mixerView != nil)
			[mixerView syncVoiceControlsFromPlayer];
	}

	if (voiceNotesView != nil)
		[voiceNotesView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (BOOL) isVoiceSoloed:(int)voice
{
	if (player == NULL)
		return NO;
	return [player isVoiceSoloed:voice];
}

// ----------------------------------------------------------------------------
- (void) toggleVoiceSolo:(int)voice
{
	if (player == NULL)
		return;

	[player toggleVoiceSoloed:voice];

	if (infoWindowController != nil)
	{
		SPMixerView* mixerView = [[infoWindowController containerView] mixerView];
		if (mixerView != nil)
			[mixerView syncVoiceControlsFromPlayer];
	}

	if (voiceNotesView != nil)
		[voiceNotesView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void) unmuteAllVoices
{
	if (player == NULL)
		return;

	[player unmuteAllVoices];

	if (infoWindowController != nil)
	{
		SPMixerView* mixerView = [[infoWindowController containerView] mixerView];
		if (mixerView != nil)
			[mixerView syncVoiceControlsFromPlayer];
	}

	if (voiceNotesView != nil)
		[voiceNotesView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (float) voiceVUPeakForVoice:(int)voice
{
	if (player == NULL)
		return 0.0f;
	return [player voiceVUPeakForVoice:voice];
}

// ----------------------------------------------------------------------------
- (NSString*) channelNoteForVoice:(int)voice
{
	if (player == NULL)
		return @"--";
	return [player channelNoteForVoice:voice];
}

// ----------------------------------------------------------------------------
- (NSString*) channelInstrumentForVoice:(int)voice
{
	if (player == NULL)
		return @"--";
	return [player channelInstrumentForVoice:voice];
}

// ----------------------------------------------------------------------------
- (int) channelPeriodForVoice:(int)voice
{
	if (player == NULL)
		return 0;
	return [player channelPeriodForVoice:voice];
}

// ----------------------------------------------------------------------------
- (int) trackerPattern
{
	if (player == NULL) return 0;
	return [player currentPattern];
}

// ----------------------------------------------------------------------------
- (int) trackerRow
{
	if (player == NULL) return 0;
	return [player currentRow];
}

// ----------------------------------------------------------------------------
- (int) trackerNumRows
{
	if (player == NULL) return 64;
	return [player numRowsInCurrentPattern];
}

// ----------------------------------------------------------------------------
- (int) trackerOrder
{
	if (player == NULL) return 0;
	return [player currentOrder];
}

// ----------------------------------------------------------------------------
- (int) trackerBPM
{
	if (player == NULL) return 125;
	return [player currentBPM];
}

// ----------------------------------------------------------------------------
- (int) trackerSpeed
{
	if (player == NULL) return 6;
	return [player currentSpeed];
}

// ----------------------------------------------------------------------------
- (int) trackerMidiNoteForVoice:(int)voice
{
	if (player == NULL) return -1;
	return [player channelMidiNoteForVoice:voice];
}

// ----------------------------------------------------------------------------
- (int) trackerVolumeForVoice:(int)voice
{
	if (player == NULL) return 0;
	return [player channelVolumeForVoice:voice];
}

// ----------------------------------------------------------------------------
- (NSString*) trackerEffectForVoice:(int)voice
{
	if (player == NULL) return @"...";
	return [player channelEffectForVoice:voice];
}

// ----------------------------------------------------------------------------
- (void) getTrackerCellForChannel:(int)ch row:(int)row note:(NSString* _Nonnull * _Nonnull)outNote ins:(NSString* _Nonnull * _Nonnull)outIns vol:(NSString* _Nonnull * _Nonnull)outVol fx:(NSString* _Nonnull * _Nonnull)outFx
{
	if (player == NULL) {
		*outNote = @"---";
		*outIns = @"..";
		*outVol = @"..";
		*outFx = @"...";
		return;
	}
	[player getTrackerCellForChannel:ch row:row note:outNote ins:outIns vol:outVol fx:outFx];
}

// ----------------------------------------------------------------------------
- (SPBrowserDataSource*) browserDataSource
{
    return browserDataSource;
}

// ----------------------------------------------------------------------------
- (SPExportController*) exportController
{
    return exportController;
}

// ----------------------------------------------------------------------------
- (NSInteger) currentTuneLengthInSeconds
{
    return currentTuneLengthInSeconds;
}

// ----------------------------------------------------------------------------
- (void) addInfoContainerView:(NSScrollView*)infoContainerScrollView
{
    infoView = infoContainerScrollView;
    
    [self addRightSubView:infoView withWidth:400.0f];
    
    /*
     NSRect frame = [infoView frame];
     frame.size.width = 400.0f;
     [infoView setFrame:frame];
     [infoView setNeedsDisplay:YES];
     
     [splitView addSubview:(NSView*)infoView];
     */
}

// ----------------------------------------------------------------------------
- (void) addTopSubView:(NSView*)subView withHeight:(float)height
{
    NSRect browserFrame = browserScrollView.frame;
    browserFrame.size.height = [rightView frame].size.height - boxView.frame.size.height;
    NSRect subViewFrame;
    NSRect newBrowserFrame;
    NSDivideRect(browserFrame, &subViewFrame, &newBrowserFrame, height, NSMaxYEdge);
    
    subView.frame = subViewFrame;
    browserScrollView.frame = newBrowserFrame;
    if (subView.window != self)
        [rightView addSubview:subView];
    [subView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void) removeTopSubView
{
    NSRect browserFrame = browserScrollView.frame;
    browserFrame.size.height = [rightView frame].size.height - boxView.frame.size.height;
    browserScrollView.frame = browserFrame;
}

// ----------------------------------------------------------------------------
- (void) addRightSubView:(NSView*)subView withWidth:(float)width
{
    NSRect splitViewFrame = splitView.frame;
    NSRect subViewFrame;
    NSRect newSplitViewFrame;
    NSDivideRect(splitViewFrame, &subViewFrame, &newSplitViewFrame, width, NSMaxXEdge);
    
    subView.frame = subViewFrame;
    splitView.frame = newSplitViewFrame;
    if (subView.window != self)
        [self.contentView addSubview:subView];
    [subView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (void) removeRightSubView
{
    splitView.frame = self.contentView.frame;
}

// ----------------------------------------------------------------------------
- (void) addAlternateBoxView:(NSView*)subView
{
    NSRect boxFrame = boxView.frame;
    
    subView.frame = boxFrame;
    [rightView addSubview:subView];
    [subView setNeedsDisplay:YES];
}

// ----------------------------------------------------------------------------
- (float) fadeVolume
{
    return fadeOutVolume;
}

// ----------------------------------------------------------------------------
- (void) setFadeVolume:(float)volume
{
    if (volumeIsMuted)
        return;
    
    float fadeVolume = gPreferences.mPlaybackVolume * volume;
    audioDriver->setVolume(fadeVolume);
}

// ----------------------------------------------------------------------------
- (void) startFadeOut
{
    if (!fadeOutInProgress)
    {
        fadeOutVolume = 1.0f;
        fadeOutInProgress = YES;
    }
}

// ----------------------------------------------------------------------------
- (void) stopFadeOut
{
    if (fadeOutInProgress)
        fadeOutInProgress = NO;
    
    fadeOutVolume = 1.0f;
    [self setFadeVolume:fadeOutVolume];
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) infoWindowMenuItem
{
    return infoWindowMenuItem;
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) mainWindowMenuItem
{
    return mainWindowMenuItem;
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) stilBrowserMenuItem
// ----------------------------------------------------------------------------
{
    return stilBrowserMenuItem;
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) analyzerWindowMenuItem
{
    return analyzerWindowMenuItem;
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) exportTaskWindowMenuItem;
{
    return exportTaskWindowMenuItem;
}

// ----------------------------------------------------------------------------
- (NSMenuItem*) addCurrentSongToPlaylistMenuItem;
{
    return addCurrentSongToPlaylistMenuItem;
}

// ----------------------------------------------------------------------------
- (SPStatusDisplayView*) statusDisplay
{
    return statusDisplay;
}

// ----------------------------------------------------------------------------
- (void) setStatusDisplay:(SPStatusDisplayView*)view
{
    statusDisplay = view;
    [self updateTuneInfo];
}

// ----------------------------------------------------------------------------
- (SPStatusDisplayView*) miniStatusDisplay
{
    return miniStatusDisplay;
}

// ----------------------------------------------------------------------------
- (SPRemixKwedOrgController*) remixKwedOrgController
{
    return remixKwedOrgController;
}

// ----------------------------------------------------------------------------
- (BOOL) isTuneLoaded
{
    return [player isTuneLoaded];
}

// ----------------------------------------------------------------------------
- (int) currentSubtune
// ----------------------------------------------------------------------------
{
    return [player getCurrentSubtune];
}

#pragma mark -
#pragma mark PlayerInfo protocol methods
- (unsigned int) currentNumberOfSamples
{
    if (audioDriver != NULL)
        return audioDriver->getNumSamplesInBuffer();
    return 0;
}
- (NSString *)currentTitle
{
    NSString *tempString;
    if ([player isTuneLoaded] && [player hasTuneInformationStrings])
        tempString = [NSString stringWithCString:[player getCurrentTitle] encoding:NSISOLatin1StringEncoding];
    else
        tempString = [NSString string];
    return tempString;
}
- (NSString *)currentAuthor
{
    NSString *tempString;
    if ([player isTuneLoaded ] && [player hasTuneInformationStrings ])
        tempString = [NSString stringWithCString:[player getCurrentAuthor] encoding:NSISOLatin1StringEncoding];
    else
        tempString = [NSString string];
    return tempString;
}

#pragma mark -
#pragma mark UI action methods
// ----------------------------------------------------------------------------
- (IBAction) clickPlayPauseButton:(id)sender
{
    if (![player isTuneLoaded])
    {
        BOOL foundPlayableItem = [browserDataSource playSelectedItem];
        if (foundPlayableItem)
            [self setPlayPauseButtonToPause:YES];
        return;
    }
    
    if (showPlayButton) {
        if ([player isPlaying])
            [player resumePlayback];
        else
            [player startPlayback];
        [self setPlayPauseButtonToPause:YES];
    } else {
        [player pausePlayback];
        [self setPlayPauseButtonToPause:NO];
    }
    
    [[SPPreferencesController sharedInstance] save];
}

// ----------------------------------------------------------------------------
- (IBAction) clickShufflePlayButton:(id)sender
{
    gPreferences.mShuffleActive = true;
    if (gPreferences.mShuffleActive && [browserDataSource playlist] != nil) {
        [browserDataSource shufflePlaylist];
        [browserDataSource startShufflePlay];
    }
    [browserDataSource setPlaybackModeControlImages];
}

// ----------------------------------------------------------------------------
- (IBAction) clickStopButton:(id)sender
{
    if (audioDriver == NULL)
        return;
    
    [player stopPlayback];
    [self setPlayPauseButtonToPause:NO];
    if (voiceNotesView != nil)
        [voiceNotesView clearNotes];
    
    [player initCurrentSubtune];
    
    [[SPPreferencesController sharedInstance] save];
}

// ----------------------------------------------------------------------------
- (IBAction) clickFastForwardButton:(id)sender
{
    BOOL isOptionPressed = NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption ? YES : NO;
    int tempo = isOptionPressed ? 88 : 75;
    [player setTempo:tempo];
    tempoSlider.integerValue = tempo;
}

// ----------------------------------------------------------------------------
- (IBAction) moveTempoSlider:(id)sender
{
    [player setTempo:(int)[sender integerValue]];
}

// ----------------------------------------------------------------------------
- (IBAction) moveVolumeSlider:(id)sender
{
    gPreferences.mPlaybackVolume = [sender floatValue] / 100.0f;
    audioDriver->setVolume(gPreferences.mPlaybackVolume);
    volumeIsMuted = NO;
    if (sender == miniVolumeSlider)
        volumeSlider.floatValue = [sender floatValue];
    else if (sender == volumeSlider)
        miniVolumeSlider.floatValue = [sender floatValue];
    [[SPMenuBarPlayerController sharedController] updateVolume];
}

// ----------------------------------------------------------------------------
- (IBAction) increaseVolume:(id)sender
{
    gPreferences.mPlaybackVolume += 0.05f;
    if (gPreferences.mPlaybackVolume > 1.0f)
        gPreferences.mPlaybackVolume = 1.0f;
    audioDriver->setVolume(gPreferences.mPlaybackVolume);
    volumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    miniVolumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    volumeIsMuted = NO;
    [[SPMenuBarPlayerController sharedController] updateVolume];
}

// ----------------------------------------------------------------------------
- (IBAction) decreaseVolume:(id)sender
{
    gPreferences.mPlaybackVolume -= 0.05f;
    if (gPreferences.mPlaybackVolume < 0.0f)
        gPreferences.mPlaybackVolume = 0.0f;
    audioDriver->setVolume(gPreferences.mPlaybackVolume);
    volumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    miniVolumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    [[SPMenuBarPlayerController sharedController] updateVolume];
}

// ----------------------------------------------------------------------------
- (IBAction) muteVolume:(id)sender
{
    if (volumeIsMuted)
    {
        volumeIsMuted = NO;
        audioDriver->setVolume(gPreferences.mPlaybackVolume);
        volumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
        miniVolumeSlider.floatValue = gPreferences.mPlaybackVolume * 100.0f;
    }
    else
    {
        volumeIsMuted = YES;
        audioDriver->setVolume(0.0f);
        volumeSlider.floatValue = 0.0f;
        miniVolumeSlider.floatValue = 0.0f;
    }
    [[SPMenuBarPlayerController sharedController] updateVolume];
}

// ----------------------------------------------------------------------------
- (IBAction) nextSubtune:(id)sender
{
    if (fadeOutInProgress)
        [self stopFadeOut];
    [player startNextSubtune];
    [self updateTuneInfo];
}

// ----------------------------------------------------------------------------
- (IBAction) previousSubtune:(id)sender
{
    if (fadeOutInProgress)
        [self stopFadeOut];
    [player startPrevSubtune];
    [self updateTuneInfo];
}

// ----------------------------------------------------------------------------
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    //check to see if the Main Menu NSMenuItem is
    //being validcated
    if([item action] == @selector(showMainWindow:))
    {
        return ![self isVisible];
    }
    
    return TRUE;
}

// ----------------------------------------------------------------------------
- (IBAction) selectSubtune:(id)sender
{
    [self switchToSubtune:[sender tag]];
}

// ----------------------------------------------------------------------------
-(IBAction) showMainWindow:(id)sender
{
    [self makeKeyAndOrderFront:self];
}

// ----------------------------------------------------------------------------
- (IBAction) toggleInfoWindow:(id)sender
{
    if (infoWindowController == nil)
    {
        infoWindowController = [[SPInfoWindowController alloc] init];
        [infoWindowController setOwnerWindow:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPPlayerInitializedNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPPlaybackSettingsChangedNotification object:self];
    }
    
    [infoWindowController toggleWindow:sender];
}

// ----------------------------------------------------------------------------
- (IBAction) toggleOscilloscopeWindow:(id)sender
{
    if (oscillosscopeWindowController == nil)
    {
        oscillosscopeWindowController = [[SPOscilloscopeWindowController alloc] initWithWindow:_oScopeWindow];
        [oscillosscopeWindowController setPlayerWindow:self];
        
    }
    [oscillosscopeWindowController toggleWindow:(id)sender];
    
}

// ----------------------------------------------------------------------------
- (IBAction) toggleInfoPane:(id)sender
{
    if (infoWindowController == nil)
    {
        infoWindowController = [[SPInfoWindowController alloc] init];
        [infoWindowController setOwnerWindow:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
    }
    
    [infoWindowController togglePane:sender];
}

// ----------------------------------------------------------------------------
- (IBAction) toggleStilBrowser:(id)sender
{
    if (stilBrowserController == nil)
    {
        stilBrowserController = [SPStilBrowserController sharedInstance];
        [stilBrowserController setOwnerWindow:self];
    }
    
    [stilBrowserController toggleWindow:sender];
}

// ----------------------------------------------------------------------------
- (IBAction) toggleAnalyzer:(id)sender
{
    /* SP Analyszer deactivated for v5.1.0
     if (analyzerWindowController == nil)
     {
     analyzerWindowController = [SPAnalyzerWindowController sharedInstance];
     [analyzerWindowController setOwnerWindow:self];
     }
     
     [analyzerWindowController toggleWindow:sender];
     */
}

// ----------------------------------------------------------------------------
- (IBAction) openFile:(id)sender
{
    if (!self.visible)
        return;
    
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.allowedFileTypes = @[@"sid", @"mod", @"xm", @"s3m", @"it", @"mtm", @"ft1", @"ft", @"med", @"okt", @"stm", @"669", @"far", @"ult"];
    
    [openPanel beginSheetModalForWindow:self completionHandler:^(NSInteger result)
     {
        if (result == NSModalResponseOK)
        {
            NSArray* urlsToOpen = openPanel.URLs;
            NSString* file = [urlsToOpen[0] path];
            
            //NSString* relativePath = [[SPCollectionUtilities sharedInstance] makePathRelativeToCollectionRoot:file];
            //if (relativePath != nil)
            //  [[SPStilBrowserController sharedInstance] displayEntryForRelativePath:relativePath];
            [self->browserDataSource addFile:file];
            
            
            [self playTuneAtPath:file];
        }
    }
    ];
    
}

// ----------------------------------------------------------------------------
- (IBAction) openUrl:(id)sender

{
    if (!self.visible)
        return;
    
    //[NSApp beginSheet:openUrlSheetPanel modalForWindow:self modalDelegate:self didEndSelector:@selector(didEndOpenUrlSheet:returnCode:contextInfo:) contextInfo:nil];
    [self beginSheet:openUrlSheetPanel completionHandler:^(NSModalResponse returnCode) {}];
}

// ----------------------------------------------------------------------------
- (void) didEndOpenUrlSheet:(NSWindow*)sheet returnCode:(int)returnCode contextInfo:(void*)contextInfo
// ----------------------------------------------------------------------------
{
    [sheet orderOut:self];
}

// ----------------------------------------------------------------------------
- (IBAction) dismissOpenUrlSheet:(id)sender
{
    if ([[sender title] isEqualToString:@"OK"])
    {
        NSString* urlString = openUrlTextField.stringValue;
        
        [self playTuneAtURL:urlString];
    }
    
    [NSApp endSheet:openUrlSheetPanel];
}

// ----------------------------------------------------------------------------
- (IBAction) openSidplayHomepage:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/Alexco500/sidplay5"]];
}

// ----------------------------------------------------------------------------
- (IBAction) openHvscHomepage:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://hvsc.c64.org/"]];
}

// ----------------------------------------------------------------------------
- (IBAction) moveFocusToSearchField:(id)sender
{
    if (stilBrowserController == nil)
        return;
    
    if (stilBrowserController.window.visible)
    {
        [stilBrowserController.window makeKeyWindow];
        [stilBrowserController.window makeFirstResponder:[stilBrowserController searchField]];
    }
    else
        [self makeFirstResponder:[browserDataSource toolbarSearchField]];
}

// ----------------------------------------------------------------------------
- (IBAction) showPreferencesWindow:(id)sender
{
    NSWindow* syncProgressDialog = [sourceListDataSource syncProgressDialog];
    if (syncProgressDialog != nil && syncProgressDialog.visible)
        return;
    
    if (prefsWindowController == nil)
    {
        prefsWindowController = [[SPPreferencesWindowController alloc] init];
        [prefsWindowController setOwnerWindow:self];
        [prefsWindowController setSourceListDataSource:sourceListDataSource];
    }
    
    [prefsWindowController showWindow:sender];
}

// ----------------------------------------------------------------------------
- (IBAction) playRandomTuneFromCollection:(id)sender
{
    NSString* path = [[SPCollectionUtilities sharedInstance] pathOfRandomCollectionItemInPath:nil];
    if (path != nil)
    {
        //NSLog(@"random tune: %@\n", path);
        [self playTuneAtPath:path];
        [browserDataSource browseToFile:path andSetAsCurrentItem:YES];
    }
}

// ----------------------------------------------------------------------------
- (IBAction) toggleVisualizerView:(id)sender
{
    if (visualizerView == nil)
        return;
    
    if (visualizerView.superview != nil)
    {
        //NSView* contentView = [self contentView];
        //[contentView addSubview:splitView];
        [visualizerView removeFromSuperview];
    }
    else
    {
        NSRect frame = splitView.frame;
        visualizerView.frame = frame;
        NSView* contentView = self.contentView;
        [contentView addSubview:visualizerView];
        //[splitView removeFromSuperview];
    }
}

// ----------------------------------------------------------------------------
- (IBAction) selectVisualizer:(id)sender
{
    if (visualizerView == nil)
        return;
    
    NSInteger index = [sender tag];
    NSArray* menuItems = [sender menu].itemArray;
    for (NSMenuItem* menuItem in menuItems)
        menuItem.state = NSOffState;
    
    [sender setState:NSOnState];
    
    NSString* visualizerPath = visualizerCompositionPaths[index];
    [visualizerView loadCompositionFromFile:visualizerPath];
}

// ----------------------------------------------------------------------------
- (void) populateVisualizerMenu
{
    NSString* defaultVisualizerPath = [NSString stringWithFormat:@"%@%@",[NSBundle mainBundle].resourcePath,@"/DefaultVisualizer.qtz"];
    visualizerCompositionPaths = [NSMutableArray arrayWithCapacity:3];
    [visualizerCompositionPaths addObject:defaultVisualizerPath];
    
    NSInteger index = 1;
    NSArray* visualizerFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[SPApplicationStorageController visualizerPath] error:nil];
    for (NSString* visualizerFile in visualizerFiles)
    {
        if ([visualizerFile characterAtIndex:0] == '.')
            continue;
        
        if (![visualizerFile.pathExtension isEqualToString:@"qtz"])
            continue;
        
        NSString* visualizerCompositionPath = [[SPApplicationStorageController visualizerPath] stringByAppendingPathComponent:visualizerFile];
        [visualizerCompositionPaths addObject:visualizerCompositionPath];
        
        NSString* name = visualizerFile.stringByDeletingPathExtension;
        NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:name action:@selector(selectVisualizer:) keyEquivalent:@""];
        menuItem.target = self;
        menuItem.tag = index;
        [visualizerMenu addItem:menuItem];
        
        index++;
    }
}

// ----------------------------------------------------------------------------
- (void) setupThemeMenu
// ----------------------------------------------------------------------------
{
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenuItem *viewMenuItem = [mainMenu itemWithTitle:@"View"];
    if (!viewMenuItem) {
        for (NSMenuItem *item in [mainMenu itemArray]) {
            if ([[item title] isEqualToString:@"View"] || [[item submenu] itemWithTitle:@"Show Toolbar"]) {
                viewMenuItem = item;
                break;
            }
        }
    }
    
    if (viewMenuItem && viewMenuItem.submenu) {
        NSMenu *viewMenu = viewMenuItem.submenu;
        if ([viewMenu itemWithTitle:@"Theme"] == nil) {
            [viewMenu addItem:[NSMenuItem separatorItem]];
            
            NSMenuItem *themeParentItem = [[NSMenuItem alloc] initWithTitle:@"Theme" action:nil keyEquivalent:@""];
            NSMenu *themeMenu = [[NSMenu alloc] initWithTitle:@"Theme"];
            
            NSArray *themes = @[
                @{@"title": @"System Default (macOS)", @"tag": @(SPAppThemeSystem)},
                @{@"title": @"Commodore 64 Classic", @"tag": @(SPAppThemeC64)},
                @{@"title": @"Amiga Workbench 1.3", @"tag": @(SPAppThemeWorkbench13)},
                @{@"title": @"Amiga Workbench 3.1", @"tag": @(SPAppThemeWorkbench31)}
            ];
            
            for (NSDictionary *t in themes) {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:t[@"title"] action:@selector(selectThemeFromMenu:) keyEquivalent:@""];
                item.target = self;
                item.tag = [t[@"tag"] integerValue];
                [themeMenu addItem:item];
            }
            
            [themeMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *cycleItem = [[NSMenuItem alloc] initWithTitle:@"Cycle Theme" action:@selector(cycleThemeFromMenu:) keyEquivalent:@"t"];
            cycleItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
            cycleItem.target = self;
            [themeMenu addItem:cycleItem];
            
            themeParentItem.submenu = themeMenu;
            [viewMenu addItem:themeParentItem];
            
            [viewMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *miniPlayerItem = [[NSMenuItem alloc] initWithTitle:@"Show Menu Bar Mini-Player" action:@selector(toggleMenuBarMiniPlayer:) keyEquivalent:@"m"];
            miniPlayerItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
            miniPlayerItem.target = self;
            miniPlayerItem.tag = 7771;
            [viewMenu addItem:miniPlayerItem];
        }
    }
    [self updateThemeMenuChecks];
}

// ----------------------------------------------------------------------------
- (void) updateThemeMenuChecks
// ----------------------------------------------------------------------------
{
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenuItem *viewMenuItem = [mainMenu itemWithTitle:@"View"];
    if (!viewMenuItem) {
        for (NSMenuItem *item in [mainMenu itemArray]) {
            if ([[item title] isEqualToString:@"View"] || [[item submenu] itemWithTitle:@"Show Toolbar"]) {
                viewMenuItem = item;
                break;
            }
        }
    }
    if (viewMenuItem && viewMenuItem.submenu) {
        NSMenuItem *themeParentItem = [viewMenuItem.submenu itemWithTitle:@"Theme"];
        if (themeParentItem && themeParentItem.submenu) {
            SPAppTheme current = [SPThemeManager sharedManager].currentTheme;
            for (NSMenuItem *item in themeParentItem.submenu.itemArray) {
                if (item.action == @selector(selectThemeFromMenu:)) {
                    item.state = (item.tag == current) ? NSControlStateValueOn : NSControlStateValueOff;
                }
            }
        }
        
        NSMenuItem *miniPlayerItem = [viewMenuItem.submenu itemWithTag:7771];
        if (miniPlayerItem) {
            miniPlayerItem.state = [SPMenuBarPlayerController sharedController].isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

// ----------------------------------------------------------------------------
- (void) setupSidebarVisualEffectView
// ----------------------------------------------------------------------------
{
    if (sidebarVisualEffectView != nil || leftView == nil) {
        return;
    }
    
    NSView *leftPane = (NSView *)leftView;
    leftPane.wantsLayer = YES;
    
    NSRect leftBounds = leftPane.bounds;
    sidebarVisualEffectView = [[NSVisualEffectView alloc] initWithFrame:leftBounds];
    sidebarVisualEffectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sidebarVisualEffectView.material = NSVisualEffectMaterialSidebar;
    sidebarVisualEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebarVisualEffectView.state = NSVisualEffectStateFollowsWindowActiveState;
    sidebarVisualEffectView.wantsLayer = YES;
    
    // Insert behind all other subviews in leftView
    [leftPane addSubview:sidebarVisualEffectView positioned:NSWindowBelow relativeTo:nil];
    
    // Ensure the source list scroll view doesn't paint an opaque background
    SPSourceListView *sView = sourceListDataSource.sourceListView;
    if (sView) {
        NSScrollView *sourceScrollView = [sView enclosingScrollView];
        if (sourceScrollView) {
            sourceScrollView.drawsBackground = NO;
            if (sourceScrollView.contentView) {
                sourceScrollView.contentView.drawsBackground = NO;
            }
        }
    }
}

// ----------------------------------------------------------------------------
- (void) applyCurrentTheme
// ----------------------------------------------------------------------------
{
    SPThemeManager *tm = [SPThemeManager sharedManager];
    NSColor *winBg = [tm windowBackgroundColor];
    if (winBg) {
        self.backgroundColor = winBg;
    } else {
        self.backgroundColor = [NSColor windowBackgroundColor];
    }
    self.appearance = [tm windowAppearance];
    
    if (sidebarVisualEffectView) {
        sidebarVisualEffectView.hidden = (tm.currentTheme != SPAppThemeSystem);
    }
    
    [boxView setNeedsDisplay:YES];
    [splitView setNeedsDisplay:YES];
    [statusDisplay setNeedsDisplay:YES];
    [spectrumView setNeedsDisplay:YES];
    if (voiceNotesView) {
        [voiceNotesView setNeedsDisplay:YES];
    }
    
    SPBrowserView *bView = browserDataSource.browserView;
    if (bView) {
        bView.backgroundColor = [tm browserBackgroundColor];
        bView.gridColor = [tm browserGridColor];
        [bView setNeedsDisplay:YES];
        [bView reloadData];
    }
    
    SPSourceListView *sView = sourceListDataSource.sourceListView;
    if (sView) {
        sView.backgroundColor = [tm sourceListBackgroundColor];
        NSScrollView *sourceScrollView = [sView enclosingScrollView];
        if (sourceScrollView) {
            sourceScrollView.drawsBackground = NO;
            if (sourceScrollView.contentView) {
                sourceScrollView.contentView.drawsBackground = NO;
            }
        }
        [sView setNeedsDisplay:YES];
        [sView reloadData];
    }
    
    [self updateThemeMenuChecks];
}

// ----------------------------------------------------------------------------
- (void) seekToSeconds:(NSInteger)seconds
// ----------------------------------------------------------------------------
{
    if (player == NULL) return;
    if (seconds < 0) seconds = 0;
    if (currentTuneLengthInSeconds > 0 && seconds > currentTuneLengthInSeconds) {
        seconds = currentTuneLengthInSeconds;
    }
    
    [player seekToSeconds:(int)seconds];
    [self updateTimer];
}

// ----------------------------------------------------------------------------
- (void) toggleLoopMode
// ----------------------------------------------------------------------------
{
    // Mode sequence: Normal (Off) -> Repeat Single Subtune -> Repeat All Subtunes -> Normal (Off)
    if (!gPreferences.mRepeatSingleActive && !gPreferences.mRepeatActive) {
        gPreferences.mRepeatSingleActive = YES;
        gPreferences.mRepeatActive = NO;
        if (spectrumView) {
            [spectrumView showNotification:@"Loop: Single Subtune 🔁1"];
        }
    } else if (gPreferences.mRepeatSingleActive) {
        gPreferences.mRepeatSingleActive = NO;
        gPreferences.mRepeatActive = YES;
        if (spectrumView) {
            [spectrumView showNotification:@"Loop: All Tracks 🔁"];
        }
    } else {
        gPreferences.mRepeatSingleActive = NO;
        gPreferences.mRepeatActive = NO;
        if (spectrumView) {
            [spectrumView showNotification:@"Loop: Off ➡️"];
        }
    }
    
    [statusDisplay setNeedsDisplay:YES];
    [miniStatusDisplay setNeedsDisplay:YES];
    [[SPMenuBarPlayerController sharedController] updateLoopMode];
}

// ----------------------------------------------------------------------------
- (BOOL) isRepeatSingleActive
// ----------------------------------------------------------------------------
{
    return gPreferences.mRepeatSingleActive;
}

// ----------------------------------------------------------------------------
- (BOOL) isRepeatAllActive
// ----------------------------------------------------------------------------
{
    return gPreferences.mRepeatActive;
}

// ----------------------------------------------------------------------------
- (BOOL) isAudioPlaying
// ----------------------------------------------------------------------------
{
    if (audioDriver != nil) {
        return audioDriver->getIsPlaying();
    }
    return (player != nil) ? [player isPlaying] : NO;
}

// ----------------------------------------------------------------------------
- (float) playbackVolume
// ----------------------------------------------------------------------------
{
    return gPreferences.mPlaybackVolume;
}

// ----------------------------------------------------------------------------
- (void) setPlaybackVolume:(float)volume
// ----------------------------------------------------------------------------
{
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    gPreferences.mPlaybackVolume = volume;
    if (audioDriver != nil) {
        audioDriver->setVolume(volume);
    }
    volumeSlider.floatValue = volume * 100.0f;
    miniVolumeSlider.floatValue = volume * 100.0f;
    volumeIsMuted = (volume == 0.0f);
    [[SPMenuBarPlayerController sharedController] updateVolume];
}

// ----------------------------------------------------------------------------
- (IBAction) toggleMenuBarMiniPlayer:(id)sender
// ----------------------------------------------------------------------------
{
    SPMenuBarPlayerController *mbc = [SPMenuBarPlayerController sharedController];
    mbc.enabled = !mbc.isEnabled;
    [self updateThemeMenuChecks];
}

// ----------------------------------------------------------------------------
- (IBAction) selectThemeFromMenu:(id)sender
// ----------------------------------------------------------------------------
{
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *item = (NSMenuItem *)sender;
        [[SPThemeManager sharedManager] applyTheme:(SPAppTheme)item.tag];
    }
}

// ----------------------------------------------------------------------------
- (IBAction) cycleThemeFromMenu:(id)sender
// ----------------------------------------------------------------------------
{
    [[SPThemeManager sharedManager] cycleTheme];
}

// ----------------------------------------------------------------------------
- (void) themeDidChangeNotification:(NSNotification *)notification
// ----------------------------------------------------------------------------
{
    [self applyCurrentTheme];
}

// ----------------------------------------------------------------------------
- (SPAppTheme) currentTheme
// ----------------------------------------------------------------------------
{
    return [SPThemeManager sharedManager].currentTheme;
}

// ----------------------------------------------------------------------------
- (void) populateSIDselector
{
    // query current SID settings and set UI accordingly
    NSMutableAttributedString *sidModel6 = [[NSMutableAttributedString alloc] initWithString:@"MOS 6581\n"];
    NSMutableAttributedString *sidModel8 = [[NSMutableAttributedString alloc] initWithString:@"MOS 8580\n"];
    NSMutableAttributedString *userDefault = [[NSMutableAttributedString alloc] initWithString:@"USER DEFAULT"];
    NSMutableAttributedString *tuneDefault = [[NSMutableAttributedString alloc] initWithString:@"TUNE DEFAULT"];
    NSMutableAttributedString *concatString = [[NSMutableAttributedString alloc] initWithString:@", "];
    [concatString addAttribute:NSFontAttributeName value:[NSFont userFontOfSize:8] range:NSMakeRange(0, 2)];
    [userDefault addAttribute:NSFontAttributeName value:[NSFont userFontOfSize:8] range:NSMakeRange(0, 12)];
    [tuneDefault addAttribute:NSFontAttributeName value:[NSFont userFontOfSize:8] range:NSMakeRange(0, 12)];
    //new text for the text fields
    NSMutableAttributedString *newText6;
    NSMutableAttributedString *newText8;
    bool addedText6 = NO;
    bool addedText8 = NO;
    
    newText6 = [[NSMutableAttributedString alloc] initWithAttributedString:sidModel6];
    newText8 = [[NSMutableAttributedString alloc] initWithAttributedString:sidModel8];
    struct PlaybackSettings dummySettings;
    [gPreferences getPlaybackSettings:&dummySettings];

    // check which SID device is set in prefs
    if (dummySettings.mSidModel == 0)
    {
        [newText6 appendAttributedString:userDefault];
        addedText6 = YES;
        // set check boxes to config defaults, will be
        // overwritten down below, if tune settings are different
        [check6 setState:NSOnState];
        [check8 setState:NSOffState];
    } else if (dummySettings.mSidModel == 1)
    {
        [newText8 appendAttributedString:userDefault];
        addedText8 = YES;
        // set check boxes to config defaults, will be
        // overwritten down below, if tune settings are different
        [check6 setState:NSOffState];
        [check8 setState:NSOnState];
    }
    // check which SID device is used in tune
    if ([player getSIDModelFromTune] == M_6581) {
        if (addedText6) {
            [newText6 appendAttributedString:concatString];
        }
        [newText6 appendAttributedString:tuneDefault];
    } else if ([player getSIDModelFromTune ] == M_8580) {
        if (addedText8) {
            [newText8 appendAttributedString:concatString];
        }
        [newText8 appendAttributedString:tuneDefault];
    }
    // set NSAttributedString accordingly
    [text6 setAttributedStringValue:newText6];
    [text8 setAttributedStringValue:newText8];
    
    // check which device is used currently
    
    [check6 setEnabled:YES];
    [check8 setEnabled:YES];
    if (!dummySettings.SIDselectorOverrideActive) {
        // SIDselector override is not active, check if we force SID in prefs
        if (!dummySettings.mForceSidModel) {
            // get default SID from tune
            if (strcmp([player getCurrentChipModel],"MOS 6581") == 0)
            {
                [check6 setState:NSOnState];
                [check8 setState:NSOffState];
            } else if (strcmp([player getCurrentChipModel],"MOS 8580") == 0)
            {
                [check6 setState:NSOffState];
                [check8 setState:NSOnState];
            }
        }
    } else {
        if (dummySettings.SIDselectorOverrideModel == 0) {
            [check6 setState:NSOnState];
            [check8 setState:NSOffState];
        } else {
            [check6 setState:NSOffState];
            [check8 setState:NSOnState];
        }
    }
    // check for EXT SID devices
    // and hide stack views accordingly
    [ExtLine1 setHidden:YES];
    [ExtLine2 setHidden:YES];
    [ExtText setHidden:YES];
    bool enable_ext1, enable_ext2, enable_ext3, enable_ext4;
    // set all off
    enable_ext1 = false;
    enable_ext2 = false;
    enable_ext3 = false;
    enable_ext4 = false;
    [stackViewExternal1 setHidden:!enable_ext1];
    [stackViewExternal2 setHidden:!enable_ext2];
    [stackViewExternal3 setHidden:!enable_ext3];
    [stackViewExternal4 setHidden:!enable_ext4];
}
// ----------------------------------------------------------------------------
- (IBAction) SIDSelectorButtonPressed:(id)sender
{
    if ([player isCurrentTuneMod]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Commodore Amiga Audio Hardware";
        alert.informativeText = @"Sound Hardware: MOS / CSG 8364 'Paula'\n• 4 hardware DMA sound channels (stereo left/right)\n• 8-bit linear pulse-code modulation (PCM)\n• Variable sampling rates up to 28.8 kHz (PAL) / 28.9 kHz (NTSC)\n• Native Amiga ProTracker / FastTracker / OctaMED playback";
        [alert runModal];
        return;
    }

    NSRect senderBounds = [sender respondsToSelector:@selector(bounds)] ? ((NSView *)sender).bounds : NSZeroRect;
    // Convert point to main window coordinates
    NSRect entryRect = [sender convertRect:senderBounds
                                    toView:[[NSApp mainWindow] contentView]];
    // Show popover
    [popoverSIDSelector showRelativeToRect:entryRect
                                    ofView:[[NSApp mainWindow] contentView]
                             preferredEdge:NSMinYEdge];
    [self populateSIDselector];
}

// ----------------------------------------------------------------------------
- (IBAction) checkEnable6:(id)sender
{
    NSButton *button = sender;
    if ([button state] == NSOnState) {
        // User wants to use MOS 6
        // deactivate all other check marks
        [check8 setState:NSOffState];
        [checkE1 setState:NSOffState];
        [checkE2 setState:NSOffState];
        [checkE3 setState:NSOffState];
        [checkE4 setState:NSOffState];
        // reconfigure replayer
        struct PlaybackSettings dummySettings;
        [gPreferences getPlaybackSettings:&dummySettings];
        dummySettings.SIDselectorOverrideActive = YES;
        dummySettings.SIDselectorOverrideModel = 0;
        if ([player isPlaying])
        {
            [player stopPlayback];
            [player initEmuEngineWithSettings:&dummySettings];
            [player startPlayback];
        } else {
            [player initEmuEngineWithSettings:&dummySettings];
        }
        [gPreferences copyPlaybackSettings:&dummySettings];
        [[SPPreferencesController sharedInstance] initializeFilterSettingsFromChipModelOfPlayer:player];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
    } else
        // you can't deselct, you can only switch with other checkboxes
        button.state = NSOnState;
    
}

// ----------------------------------------------------------------------------
- (IBAction) checkEnable8:(id)sender
{
    NSButton *button = sender;
    if ([button state] == NSOnState) {
        // User wants to use MOS 8
        // deactivate all other check marks
        [check6 setState:NSOffState];
        [checkE1 setState:NSOffState];
        [checkE2 setState:NSOffState];
        [checkE3 setState:NSOffState];
        [checkE4 setState:NSOffState];
        struct PlaybackSettings dummySettings;
        [gPreferences getPlaybackSettings:&dummySettings];

        // reconfigure replayer
        dummySettings.SIDselectorOverrideActive = YES;
        dummySettings.SIDselectorOverrideModel = 1;
        
        [gPreferences copyPlaybackSettings:&dummySettings];
        if ([player isPlaying])
        {
            [player stopPlayback];
            [player initEmuEngineWithSettings:&dummySettings];
            [player startPlayback];
        } else {
            [player initEmuEngineWithSettings:&dummySettings];
        }
        [[SPPreferencesController sharedInstance] initializeFilterSettingsFromChipModelOfPlayer:player];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
    } else
        // you can't deselct, you can only switch with other checkboxes
        button.state = NSOnState;
}

// ----------------------------------------------------------------------------
- (IBAction) resetSIDSelector:(id)sender
{
    struct PlaybackSettings dummySettings;
    [gPreferences getPlaybackSettings:&dummySettings];
    dummySettings.SIDselectorOverrideActive = NO;
    dummySettings.SIDselectorOverrideModel = 0;
    // reconfigure replayer
    if ([player isPlaying])
    {
        [player stopPlayback];
        [player initEmuEngineWithSettings:&dummySettings];
        [player startPlayback];
    } else {
        [player initEmuEngineWithSettings:&dummySettings];
    }
    [gPreferences copyPlaybackSettings:&dummySettings];
    [[SPPreferencesController sharedInstance] initializeFilterSettingsFromChipModelOfPlayer:player];
    [self populateSIDselector];
    [[NSNotificationCenter defaultCenter] postNotificationName:SPTuneChangedNotification object:self];
}

// ----------------------------------------------------------------------------
- (IBAction) addCurrentSongToPlaylist:(id)sender
{
    int subSong = 0;
    if ([player isTuneLoaded]) {
        subSong = [player getCurrentSubtune];
        [sourceListDataSource addSongToPlaylist:currentTunePath withSubtune: subSong];
    }
}

#pragma mark -
#pragma mark application delegate methods

// ----------------------------------------------------------------------------
- (BOOL) application:(NSApplication*)theApplication openFile:(NSString*)filename
{
    /*
     NSString* relativePath = [[SPCollectionUtilities sharedInstance] makePathRelativeToCollectionRoot:filename];
     NSLog(@"SIDPlayer -- rel Path: %@", relativePath);
     if (relativePath != nil)
     [[SPStilBrowserController sharedInstance] displayEntryForRelativePath:relativePath];
     NSLog(@"SIDPlayer-- name : %@", filename);
     */
    [self->browserDataSource addFile:filename];
    [self playTuneAtPath:filename];
    return YES;
}

// ----------------------------------------------------------------------------
- (void) applicationDidFinishLaunching:(NSNotification*)notification
{
    NSTimer* slowTimer = [NSTimer scheduledTimerWithTimeInterval:10.0f target:self selector:@selector(updateSlowTimer) userInfo:nil repeats:YES];
    NSTimer* normalTimer = [NSTimer scheduledTimerWithTimeInterval:0.05f target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
    NSTimer* fastTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/60.0f target:self selector:@selector(updateFastTimer) userInfo:nil repeats:YES];
    
    [[NSRunLoop currentRunLoop] addTimer:slowTimer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:normalTimer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:fastTimer forMode:NSEventTrackingRunLoopMode];
    
    //[NSTimer scheduledTimerWithTimeInterval:1.0f target:statusDisplay selector:@selector(startLogoRendering) userInfo:nil repeats:NO];
    
    NSWindow* syncProgressDialog = [sourceListDataSource syncProgressDialog];
    if (syncProgressDialog != nil && !syncProgressDialog.visible)
        [self makeKeyAndOrderFront:self];
        
    [[SPMenuBarPlayerController sharedController] setupWithPlayerWindow:self];
}

// ----------------------------------------------------------------------------
- (void) applicationDidResignActive:(NSNotification*)notification
{
    
}

// ----------------------------------------------------------------------------
- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)application
{
    return NO;
}

// ----------------------------------------------------------------------------
- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication*)sender
{
    if ([exportController activeExportTasksCount] > 0)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"You have active export tasks, do you really want to quit SIDPLAY?"];
        [alert setInformativeText:@"If you decide to quit, the files that are currently being exported will be incomplete or damaged."];
        [alert setAlertStyle:NSAlertStyleInformational]; // or NSAlertStyleWarning, or NSAlertStyleCritical
        [alert addButtonWithTitle:@"Don't Quit"];
        [alert addButtonWithTitle:@"Quit"];
        
        NSInteger result = [alert runModal];
        
        if (result == NSAlertFirstButtonReturn)
            return NSTerminateCancel;
    }
    
    [statusDisplay prepareForQuit];
    if ([self audioDriverIsPlaying]) {
        [self audioDriverStopPlaying];
    }
    
    return NSTerminateNow;
}

// ----------------------------------------------------------------------------
- (void) applicationWillTerminate:(NSNotification*)aNotification
{
    //NSLog(@"Shutting down");
    [[SPPreferencesController sharedInstance] save];
}

// ----------------------------------------------------------------------------
- (NSMenu*) applicationDockMenu:(NSApplication*)sender
{
    return dockTileMenu;
}

// ----------------------------------------------------------------------------
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    if (flag) {
        return NO;
    }
    else
    {
        [self makeKeyAndOrderFront:self];// Window that you want open while click on dock app icon
        return YES;
    }
}

#pragma mark -
#pragma mark split view delegate methods

// ----------------------------------------------------------------------------
- (NSRect )splitView:(NSSplitView *)theSplitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
    {
        NSRect leftViewFrame = [leftView frame];
        const int bottom_bar_height = 23;
        NSRect gripRect = NSMakeRect(NSWidth(leftViewFrame) - 17, NSHeight(leftViewFrame) - bottom_bar_height, 17, bottom_bar_height);
        
        return gripRect;
    }
    
    return NSZeroRect;
}

// ----------------------------------------------------------------------------
- (BOOL) splitView:(NSSplitView*)splitView canCollapseSubview:(NSView*) subview
{
    return NO;
}

// ----------------------------------------------------------------------------
- (CGFloat) splitView:(NSSplitView*)sender constrainSplitPosition:(CGFloat) proposedPosition ofSubviewAt:(NSInteger) offset
{
    if (offset == 0)
    {
        float position = fminf(proposedPosition, 400.0f);
        position = fmaxf(position, 100.0f);
        
        return position;
    }
    
    /*
     if (offset == 1)
     {
     float idealPosition = [sender frame].size.width - 400.0f;
     return idealPosition;
     //return fminf(idealPosition, proposedPosition);
     }
     
     if (offset == 2)
     {
     return 400.0f;
     //return fminf(idealPosition, proposedPosition);
     }
     */
    
    return proposedPosition;
}

// ----------------------------------------------------------------------------
- (NSRect) splitView:(NSSplitView *)sender effectiveRect:(NSRect)proposedEffectiveRect forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)dividerIndex
{
    return NSInsetRect(proposedEffectiveRect, -2.0f, 0.0f);
}

// ----------------------------------------------------------------------------
- (BOOL) splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
    return NO;
}

// ----------------------------------------------------------------------------
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    return nil;
}

@end

@implementation SPWindowDelegate
// ----------------------------------------------------------------------------
- (BOOL) windowShouldZoom:(NSWindow*)window toFrame:(NSRect)proposedFrame
{
    if (window == mainPlayerWindow)
    {
        BOOL logoVisible = [[mainPlayerWindow statusDisplay] logoVisible];
        BOOL displayVisible = [[mainPlayerWindow statusDisplay] displayVisible];
        [[mainPlayerWindow miniStatusDisplay] setLogoVisible:logoVisible];
        [[mainPlayerWindow miniStatusDisplay] setDisplayVisible:displayVisible];
        
        [window setIsVisible:NO];
        [miniPlayerPanel setIsVisible:YES];
    }
    else
    {
        BOOL logoVisible = [[mainPlayerWindow miniStatusDisplay] logoVisible];
        BOOL displayVisible = [[mainPlayerWindow miniStatusDisplay] displayVisible];
        [[mainPlayerWindow statusDisplay] setLogoVisible:logoVisible];
        [[mainPlayerWindow statusDisplay] setDisplayVisible:displayVisible];
        
        [window setIsVisible:NO];
        [mainPlayerWindow setIsVisible:YES];
    }
    
    return NO;
}

// ----------------------------------------------------------------------------
- (NSSize) windowWillResize:(NSWindow*)window toSize:(NSSize)proposedFrameSize
{
    if (window == (NSWindow*)miniPlayerPanel)
    {
        if (proposedFrameSize.width < 310.0f)
            proposedFrameSize.width = 131.0f;
        
        if (proposedFrameSize.width > 300.0f)
            proposedFrameSize.width = 506.0f;
    }
    
    return proposedFrameSize;
}

@end
