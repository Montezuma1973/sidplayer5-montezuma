#import "SPExporter.h"
#import "SPExportController.h"
#import "SPPlayerWindow.h"
#import "PlayerLibSidplayWrapper.h"
#import "SongLengthDatabase.h"
#import "SPCollectionUtilities.h"
#import "SPPreferencesController.h"
#import "SPModPlayer.h"
#import "SPNowPlayingArtworkGenerator.h"

#include "TargetConditionals.h"
#include <lame/lame.h>

static NSString* exportFileTypeExtensions[NUM_EXPORT_TYPES] =
{
	@"mp3",
	@"m4a",
	@"m4a",
	@"aiff",
	@"prg",
	@"wav",
	@"flac",
	@"sid"
};

static AudioFileTypeID exportAudioFileIDs[NUM_EXPORT_TYPES] =
{
	kAudioFileMP3Type,
	kAudioFileM4AType,
	kAudioFileM4AType,
	kAudioFileAIFFType,
	0,
	kAudioFileWAVEType,
	kAudioFileFLACType,
	0
};

@implementation SPExporter

// ----------------------------------------------------------------------------
- (instancetype) init
// ----------------------------------------------------------------------------
{
    return [self initWithItem:nil withController:nil andWindow:nil loadNow:NO];
}

// ----------------------------------------------------------------------------
- (instancetype) initWithItem:(SPExportItem*)item withController:(SPExportController*)theController andWindow:(SPPlayerWindow*)window loadNow:(BOOL)loadItem
// ----------------------------------------------------------------------------
{
	self = [super init];
	if (self != nil)
	{
		controller = theController;
		ownerWindow = window;
		
		outputFileRef = NULL;
		exportSettings = [controller exportSettings];
		
		samplesRemaining = 0;
		samplesCompleted = 0;
		
		fileName = nil;
		exportProgress = 0.0f;
		fileIcon = nil;
		
		exportItemLoaded = NO;
		exportInProgress = NO;
		[self setExportStopped:NO];
		[self setExportProgressIsIndeterminate:NO];
		
		psid64Task = nil;
		
        player = [[PlayerLibSidplayWrapper alloc] init];
        struct PlaybackSettings dummy;
        [gPreferences getPlaybackSettings:&dummy];
        [player initEmuEngineWithSettings:&dummy];
		exportItem = item;

		title = [item title];
		author = [item author];

		if (loadItem)
		{
			BOOL itemIsValid = [self loadExportItem];
			if (!itemIsValid)
				return nil;
		}
		
		destinationPath = nil;
	}
	return self;
}


// ----------------------------------------------------------------------------
- (BOOL) loadExportItem
// ----------------------------------------------------------------------------
{
	if (exportItemLoaded)
		return NO;
    [gPreferences getPlaybackSettings:&settings];

	NSString* path = [exportItem path];
	int subtune = [exportItem subtune];
    bool success = [player loadTuneByPath:
                    [path cStringUsingEncoding:NSUTF8StringEncoding]
                                  subtune: subtune withSettings:&settings];
	if (!success)
		return NO;

    exportSettings.mTimeInSeconds = [[SongLengthDatabase sharedInstance] getSongLengthByPath:path andSubtune:subtune];
    if (exportSettings.mTimeInSeconds == 0 && [SPModPlayer isModFile:path])
        exportSettings.mTimeInSeconds = [SPModPlayer getModLengthForPath:path andSubtune:subtune];
    if (exportSettings.mTimeInSeconds == 0)
        exportSettings.mTimeInSeconds = gPreferences.mDefaultPlayTime;
	if ([exportItem loopCount] > 0)
        exportSettings.mTimeInSeconds *= [exportItem loopCount];

	releaseInfo = [NSString stringWithCString:[player getCurrentReleaseInfo] encoding:NSISOLatin1StringEncoding];

	exportItemLoaded = YES;

	return YES;
}


// ----------------------------------------------------------------------------
- (void) unloadExportItem
// ----------------------------------------------------------------------------
{
	if (!exportItemLoaded)
		return;
	
	exportItemLoaded = NO;
}	


// ----------------------------------------------------------------------------
- (ExportSettings *) exportSettings
// ----------------------------------------------------------------------------
{
	return exportSettings;
}


// ----------------------------------------------------------------------------
- (void) setExportSettings:(ExportSettings *)theExportSettings
// ----------------------------------------------------------------------------
{
	exportSettings = theExportSettings;
}


// ----------------------------------------------------------------------------
- (void) determineExportFilePath:(NSString*)directoryPath
// ----------------------------------------------------------------------------
{
	NSString* suggestedFilename = [self suggestedFilename];
	NSString* suggestedFilenameWithoutExtension = suggestedFilename.stringByDeletingPathExtension;
	NSString* suggestedExtension = [self suggestedFileExtension]; 

	NSString* filename = [suggestedFilenameWithoutExtension stringByAppendingPathExtension:suggestedExtension];
	
	NSString* destinationFile = [directoryPath stringByAppendingPathComponent:filename];
	
	int retryCount = 1;
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:destinationFile];
	while (exists)
	{
		filename = [suggestedFilenameWithoutExtension stringByAppendingFormat:@" %d", retryCount];
		filename = [filename stringByAppendingPathExtension:suggestedExtension];
		
		destinationFile = [directoryPath stringByAppendingPathComponent:filename];
		
		retryCount++;
		exists = [[NSFileManager defaultManager] fileExistsAtPath:destinationFile];
	}

	[self setDestinationPath:destinationFile];
}


// ----------------------------------------------------------------------------
- (NSString*) suggestedFileExtension
// ----------------------------------------------------------------------------
{
	return exportFileTypeExtensions[exportSettings.mFileType];
}


// ----------------------------------------------------------------------------
- (NSString*) suggestedFilename
// ----------------------------------------------------------------------------
{
	NSRange slashRange = [author rangeOfString:@"/"];
	NSString* authorWithoutGroup = nil;
	if (slashRange.location == NSNotFound)
		authorWithoutGroup = author;
	else
		authorWithoutGroup = [author substringToIndex:slashRange.location];

	authorWithoutGroup = [authorWithoutGroup stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	NSString* titleWithoutSlashes = [title stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	return [NSString stringWithFormat:@"%@ - %@ (song %d).%@", authorWithoutGroup, titleWithoutSlashes, [exportItem subtune], exportFileTypeExtensions[exportSettings.mFileType]];
}


// ----------------------------------------------------------------------------
- (void) setFileName:(NSString*)name
// ----------------------------------------------------------------------------
{
	fileName = name;
}


// ----------------------------------------------------------------------------
- (NSString*) fileName
// ----------------------------------------------------------------------------
{
	return fileName;
}


// ----------------------------------------------------------------------------
- (void) setDestinationPath:(NSString*)path
// ----------------------------------------------------------------------------
{
	destinationPath = path;
	[self setFileName:path.lastPathComponent];
}


// ----------------------------------------------------------------------------
- (PlayerLibSidplayWrapper*) player
// ----------------------------------------------------------------------------
{
	return player;
}


// ----------------------------------------------------------------------------
- (NSImage*) fileIcon
// ----------------------------------------------------------------------------
{
	return fileIcon;
}


// ----------------------------------------------------------------------------
- (void) setFileIcon:(NSImage*)icon
// ----------------------------------------------------------------------------
{
	fileIcon = icon;
}


// ----------------------------------------------------------------------------
- (BOOL) exportInProgress
// ----------------------------------------------------------------------------
{
	return exportInProgress;
}


// ----------------------------------------------------------------------------
- (BOOL) exportStopped
// ----------------------------------------------------------------------------
{
	return exportStopped;
}


// ----------------------------------------------------------------------------
- (void) setExportStopped:(BOOL)stopped
// ----------------------------------------------------------------------------
{
	exportStopped = stopped;
}


// ----------------------------------------------------------------------------
- (float) exportProgress
// ----------------------------------------------------------------------------
{
	return exportProgress;
}


// ----------------------------------------------------------------------------
- (void) setExportProgress:(float)progress
// ----------------------------------------------------------------------------
{
	exportProgress = progress;
}


// ----------------------------------------------------------------------------
- (BOOL) exportProgressIsIndeterminate
// ----------------------------------------------------------------------------
{
	return exportProgressIsIndeterminate;
}


// ----------------------------------------------------------------------------
- (void) setExportProgressIsIndeterminate:(BOOL)indeterminate
// ----------------------------------------------------------------------------
{
	exportProgressIsIndeterminate = indeterminate;
}


// ----------------------------------------------------------------------------
- (void) startExport
// ----------------------------------------------------------------------------
{
	samplesRemaining = exportSettings.mTimeInSeconds * settings.mFrequency;
	samplesCompleted = 0;
	exportProgress = 0.0f;
	
	[self setExportStopped:NO];
	exportInProgress = YES;
	
	if (exportSettings.mFileType == EXPORT_TYPE_MP3)
		[NSThread detachNewThreadSelector:@selector(exportUsingLameThread:) toTarget:self withObject:nil];
	else if (exportSettings.mFileType == EXPORT_TYPE_PRG)
		[self exportUsingPsid64];
	else
		[NSThread detachNewThreadSelector:@selector(exportUsingExtAudioFileThread:) toTarget:self withObject:nil];
}


// ----------------------------------------------------------------------------
- (void) stopExport
// ----------------------------------------------------------------------------
{
	[self setExportStopped:YES];
	if (!exportInProgress)
		[controller exportFinished:self];
}


// ----------------------------------------------------------------------------
- (void) revealExportFile
// ----------------------------------------------------------------------------
{
	if (destinationPath != nil)
	{
		NSWorkspace* workSpace = [NSWorkspace sharedWorkspace];
		[workSpace selectFile:destinationPath inFileViewerRootedAtPath:@""];
	}
}


// ----------------------------------------------------------------------------
- (void) exportUsingPsid64
// ----------------------------------------------------------------------------
{
	[self setExportProgressIsIndeterminate:YES];
	
	//NSString* psid64ExecutablePath = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"psid64"];
    //macOS executables should reside in executable folders for signing
    NSString* psid64ExecutablePath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"psid64"];

    NSMutableArray* psid64Arguments = [NSMutableArray arrayWithCapacity:3];

	if (exportSettings.mBlankScreen)
		[psid64Arguments addObject:@"-b"];
		
	if (exportSettings.mIncludeStilComment)
		[psid64Arguments addObject:@"-g"];

	if (exportSettings.mCompressOutputFile)
		[psid64Arguments addObject:@"-c"];

	[psid64Arguments addObject:@"-v"];

	[psid64Arguments addObject:[NSString stringWithFormat:@"-i %d", [exportItem subtune]]];
	//[psid64Arguments addObject:[NSString stringWithFormat:@"-r %@", [[SPCollectionUtilities sharedInstance] rootPath]]];
	[psid64Arguments addObject:[NSString stringWithFormat:@"-s %@", [[SongLengthDatabase sharedInstance] databasePath]]];
	[psid64Arguments addObject:[NSString stringWithFormat:@"-o%@", destinationPath]];
	[psid64Arguments addObject:[exportItem path]];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(psid64TaskFinished:) name:NSTaskDidTerminateNotification object:nil];	
	psid64Task = [[NSTask alloc] init];
	psid64Task.launchPath = psid64ExecutablePath;
	psid64Task.currentDirectoryPath = [NSBundle mainBundle].resourcePath;
	psid64Task.arguments = psid64Arguments;
	[psid64Task launch];
}


// ----------------------------------------------------------------------------
- (void) psid64TaskFinished:(NSNotification*)aNotification
// ----------------------------------------------------------------------------
{
	NSTask* task = (NSTask*) aNotification.object;
	if (task != psid64Task)
		return;

	psid64Task = nil;
	
	NSNumber* creatorCode = [NSNumber numberWithUnsignedLong:'C=64'];
	NSNumber* typeCode = [NSNumber numberWithUnsignedLong:'C64F'];
	NSDictionary* attributes = @{NSFileHFSCreatorCode: creatorCode, NSFileHFSTypeCode: typeCode};
	[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:destinationPath error:nil];

	NSImage* icon = [[NSWorkspace sharedWorkspace] iconForFile:destinationPath];
	//[icon setScalesWhenResized:NO];
	icon.size = NSMakeSize(32, 32);
	[self setFileIcon:icon];

	exportInProgress = NO;
	[self setExportStopped:YES];
	[controller exportFinished:self];
	[self setExportProgressIsIndeterminate:NO];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


// ----------------------------------------------------------------------------
- (void) exportUsingExtAudioFileThread:(id)inObject
// ----------------------------------------------------------------------------
{
    OSStatus err = noErr;

	[NSThread setThreadPriority:[NSThread threadPriority]+.1];
    
    // create the file
    if (outputFileRef == NULL)
	{
		// NSString* directory = destinationPath.stringByDeletingLastPathComponent;
		// NSString* filename = [[NSString alloc] initWithString:destinationPath.lastPathComponent];
        
        NSURL* fileUrl = [[NSURL alloc] initFileURLWithPath:destinationPath];

		BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:destinationPath];
		if (exists)
			[[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];

		//FSRef directoryFileRef;
		//err = FSPathMakeRef((const UInt8*)directory.fileSystemRepresentation, &directoryFileRef, NULL);

		BOOL isStereo = [player isCurrentTuneMod] || (settings.mStereo || [player getSidChips] > 1);
		int channels = isStereo ? 2 : 1;

		// The format in which we render the output
		inputFormat.mChannelsPerFrame = channels;
		inputFormat.mSampleRate = settings.mFrequency;
		inputFormat.mFormatID = kAudioFormatLinearPCM;
#if TARGET_RT_LITTLE_ENDIAN
		inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
#else
		inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
#endif
		inputFormat.mBytesPerPacket = sizeof(short) * inputFormat.mChannelsPerFrame;
		inputFormat.mFramesPerPacket = 1;
		inputFormat.mBytesPerFrame = sizeof(short) * inputFormat.mChannelsPerFrame;
		inputFormat.mBitsPerChannel = 16;

		// The format for the output file
		UInt32 size = sizeof(outputFormat);

		outputFormat.mSampleRate = settings.mFrequency;
		outputFormat.mChannelsPerFrame = channels;

		switch (exportSettings.mFileType)
		{
			case EXPORT_TYPE_AAC:
				outputFormat.mFormatID = kAudioFormatMPEG4AAC;
				outputFormat.mFormatFlags = 0;
				err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &outputFormat);
				break;

			case EXPORT_TYPE_ALAC:
				outputFormat.mFormatID = kAudioFormatAppleLossless;
				outputFormat.mFormatFlags = 0;
				err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &outputFormat);
				break;

			case EXPORT_TYPE_FLAC:
				outputFormat.mFormatID = kAudioFormatFLAC;
				outputFormat.mFormatFlags = 0;
				err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &outputFormat);
				break;

			case EXPORT_TYPE_WAV:
				outputFormat.mFormatID = kAudioFormatLinearPCM;
				outputFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
				outputFormat.mBytesPerPacket = sizeof(short) * outputFormat.mChannelsPerFrame;
				outputFormat.mFramesPerPacket = 1;
				outputFormat.mBytesPerFrame = sizeof(short) * outputFormat.mChannelsPerFrame;
				outputFormat.mBitsPerChannel = 16;
				break;

			case EXPORT_TYPE_AIFF:
			default:
				outputFormat.mFormatID = kAudioFormatLinearPCM;
				outputFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked;
				outputFormat.mBytesPerPacket = sizeof(short) * outputFormat.mChannelsPerFrame;
				outputFormat.mFramesPerPacket = 1;
				outputFormat.mBytesPerFrame = sizeof(short) * outputFormat.mChannelsPerFrame;
				outputFormat.mBitsPerChannel = 16;
				break;
		}
		
		err = ExtAudioFileCreateWithURL((__bridge CFURLRef)fileUrl, exportAudioFileIDs[exportSettings.mFileType], &outputFormat, NULL, kAudioFileFlags_EraseFile, &outputFileRef);

		err = ExtAudioFileSetProperty(outputFileRef, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &inputFormat);

		// Embed metadata and album artwork via underlying AudioFileID
		UInt32 audioFileIdSize = sizeof(AudioFileID);
		AudioFileID audioFileId = NULL;
		OSStatus afErr = ExtAudioFileGetProperty(outputFileRef, kExtAudioFileProperty_AudioFile, &audioFileIdSize, &audioFileId);
		if (afErr == noErr && audioFileId != NULL)
		{
			NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
			if (title.length > 0) [infoDict setObject:title forKey:(id)CFSTR(kAFInfoDictionary_Title)];
			if (author.length > 0) [infoDict setObject:author forKey:(id)CFSTR(kAFInfoDictionary_Artist)];
			
			NSString *album = @"";
			if ([player isCurrentTuneMod]) {
				const char *fmt = [player getCurrentFormat];
				NSString *fmtStr = (fmt && strlen(fmt) > 0) ? [NSString stringWithUTF8String:fmt] : @"Amiga Tracker Module";
				album = [NSString stringWithFormat:@"Amiga Module (%@)", fmtStr];
			} else {
				album = (releaseInfo.length > 0) ? releaseInfo : @"Commodore 64 SID";
			}
			[infoDict setObject:album forKey:(id)CFSTR(kAFInfoDictionary_Album)];
			[infoDict setObject:[NSString stringWithFormat:@"%d", [exportItem subtune]] forKey:(id)CFSTR(kAFInfoDictionary_TrackNumber)];
			if (releaseInfo.length >= 4) {
				[infoDict setObject:[releaseInfo substringWithRange:NSMakeRange(0, 4)] forKey:(id)CFSTR(kAFInfoDictionary_Year)];
			}
			[infoDict setObject:([player isCurrentTuneMod] ? @"Amiga Module" : @"Chiptune / C64 SID") forKey:(id)CFSTR(kAFInfoDictionary_Genre)];
			[infoDict setObject:@"Exported with SIDPLAY 5 for Mac" forKey:(id)CFSTR(kAFInfoDictionary_Comments)];
			[infoDict setObject:[NSString stringWithFormat:@"%lu", (unsigned long)exportSettings.mTimeInSeconds] forKey:(id)CFSTR(kAFInfoDictionary_ApproximateDurationInSeconds)];
			
			CFDictionaryRef cfInfo = (__bridge CFDictionaryRef)infoDict;
			AudioFileSetProperty(audioFileId, kAudioFilePropertyInfoDictionary, sizeof(CFDictionaryRef), &cfInfo);
			
			NSString *chipName = @"MOS 6581";
			if ([player isCurrentTuneMod]) {
				chipName = @"PAULA 8364";
			} else {
				const char *rawChip = [player getCurrentChipModel];
				if (rawChip && strlen(rawChip) > 0) {
					chipName = [NSString stringWithUTF8String:rawChip];
				}
			}
			NSImage *coverArt = [SPNowPlayingArtworkGenerator artworkForTitle:title
																	  artist:author
																	   isMod:[player isCurrentTuneMod]
																   chipModel:chipName
																	 subtune:[exportItem subtune]
																subtuneCount:[player getSubtuneCount]
																		size:CGSizeMake(600, 600)];
			if (coverArt) {
				CGImageRef cgRef = [coverArt CGImageForProposedRect:NULL context:nil hints:nil];
				if (cgRef) {
					NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
					NSData *jpegData = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @(0.90f)}];
					if (jpegData && jpegData.length > 0) {
						AudioFileSetProperty(audioFileId, kAudioFilePropertyAlbumArtwork, (UInt32)jpegData.length, jpegData.bytes);
					}
				}
			}
		}
		
		if (exportSettings.mFileType == EXPORT_TYPE_AAC)
		{
			size = sizeof(AudioConverterRef);
			AudioConverterRef converterRef;
			err = ExtAudioFileGetProperty(outputFileRef, kExtAudioFileProperty_AudioConverter, &size, &converterRef);
			
			UInt32 mode = exportSettings.mUseVBR ? kAudioCodecBitRateFormat_VBR : kAudioCodecBitRateFormat_CBR;
			err	= AudioConverterSetProperty(converterRef, kAudioCodecBitRateFormat, sizeof(mode), &mode);
			
			UInt32 bitRate = exportSettings.mBitRate * 1000;
			err = AudioConverterSetProperty(converterRef, kAudioConverterEncodeBitRate, sizeof(UInt32), &bitRate);
			
			UInt32 codecQuality = kAudioConverterQuality_Medium;
			int quality = exportSettings.mQuality * 4;
			switch (quality)
			{
				case 0:
					codecQuality = kAudioConverterQuality_Min;
					break;
				case 1:
					codecQuality = kAudioConverterQuality_Low;
					break;
				case 2:
					codecQuality = kAudioConverterQuality_Medium;
					break;
				case 3:
					codecQuality = kAudioConverterQuality_High;
					break;
				case 4:
					codecQuality = kAudioConverterQuality_Max;
					break;
			}

			err = AudioConverterSetProperty(converterRef, kAudioConverterCodecQuality, sizeof(UInt32), &codecQuality);
		}
		
		err = ExtAudioFileWriteAsync(outputFileRef, 0, NULL);
    }
    
	const int maxSamplesPerSlice = 64 * 1024;
	const int fadeTimeInSamples = exportSettings.mFadeOutTime * settings.mFrequency;

	AudioBufferList outputBufferList;
	UInt32 renderBufferSize = (maxSamplesPerSlice * inputFormat.mBytesPerFrame);
    char* renderBuffer = malloc(sizeof(char)*renderBufferSize);

    if (renderBuffer == nil)
        return;
	outputBufferList.mNumberBuffers = 1;
	outputBufferList.mBuffers[0].mNumberChannels = inputFormat.mChannelsPerFrame;
	outputBufferList.mBuffers[0].mData = renderBuffer;
	outputBufferList.mBuffers[0].mDataByteSize = renderBufferSize;
    // loop until stopped from an external event, or finished the entire extraction
	while (!exportStopped)
	{
        if (samplesRemaining == 0)
			break;

		// progress update
		NSNumber* progress = @((float)samplesCompleted / (float)(samplesCompleted + samplesRemaining));
		[self performSelectorOnMainThread:@selector(exportInProgressNotification:) withObject:progress waitUntilDone:NO];
		
		UInt32 numSamplesThisSlice = (int)samplesRemaining;
		if (numSamplesThisSlice > maxSamplesPerSlice)
			numSamplesThisSlice = maxSamplesPerSlice;

		// write it to the file
		if (numSamplesThisSlice > 0)
		{
			UInt32 sliceBytes = numSamplesThisSlice * inputFormat.mBytesPerFrame;
            [player fillBuffer:outputBufferList.mBuffers[0].mData withLen:sliceBytes];
            
			if (exportSettings.mWithFadeOut && (samplesRemaining - numSamplesThisSlice) < fadeTimeInSamples)
			{
				short* sampleBuffer = (short*) renderBuffer;
				int ch = inputFormat.mChannelsPerFrame;
				for(int i = 0; i < numSamplesThisSlice; i++)
				{
					if ((samplesRemaining - i) < fadeTimeInSamples)
					{
						float fadeOutFactor = (float)(samplesRemaining - i) / (float)(fadeTimeInSamples);
						for (int c = 0; c < ch; c++) {
							sampleBuffer[i * ch + c] = (short)(fadeOutFactor * sampleBuffer[i * ch + c]);
						}
					}
				}
			}

			outputBufferList.mBuffers[0].mDataByteSize = sliceBytes;
			err = ExtAudioFileWriteAsync(outputFileRef, numSamplesThisSlice, &outputBufferList);
			if (err != noErr)
				break;
		}
		
		samplesRemaining -= numSamplesThisSlice;
		samplesCompleted += numSamplesThisSlice;
    }

	free(renderBuffer);
		
    if (outputFileRef != NULL)
		ExtAudioFileDispose(outputFileRef);

	// Set Finder custom icon to retro cover art
	NSString *chipName = @"MOS 6581";
	if ([player isCurrentTuneMod]) {
		chipName = @"PAULA 8364";
	} else {
		const char *rawChip = [player getCurrentChipModel];
		if (rawChip && strlen(rawChip) > 0) {
			chipName = [NSString stringWithUTF8String:rawChip];
		}
	}
	NSImage *coverArt = [SPNowPlayingArtworkGenerator artworkForTitle:title
															  artist:author
															   isMod:[player isCurrentTuneMod]
														   chipModel:chipName
															 subtune:[exportItem subtune]
														subtuneCount:[player getSubtuneCount]
																size:CGSizeMake(600, 600)];
	if (coverArt) {
		[[NSWorkspace sharedWorkspace] setIcon:coverArt forFile:destinationPath options:0];
		[self performSelectorOnMainThread:@selector(setFileIcon:) withObject:coverArt waitUntilDone:NO];
	}
 	
	//NSLog(@"file written!\n");
	
	[self performSelectorOnMainThread:@selector(exportCompletedNotification:)
                                                withObject:(id)[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]
												waitUntilDone:NO];
	
}


// ----------------------------------------------------------------------------
- (void) exportUsingLameThread:(id)inObject
// ----------------------------------------------------------------------------
{
	[NSThread setThreadPriority:[NSThread threadPriority]+.1];

    OSStatus err = noErr;

	FILE* outputFileHandle = fopen(destinationPath.fileSystemRepresentation, "wb");

	NSImage* icon = [[NSWorkspace sharedWorkspace] iconForFile:destinationPath];
	//[icon setScalesWhenResized:NO];
	icon.size = NSMakeSize(32, 32);
	[self performSelectorOnMainThread:@selector(setFileIcon:) withObject:icon waitUntilDone:NO];

	BOOL isStereo = [player isCurrentTuneMod] || (settings.mStereo || [player getSidChips] > 1);
	int channels = isStereo ? 2 : 1;

	lame_global_flags *lameState;
	lameState = lame_init();
	if (channels == 2) {
		lame_set_mode(lameState, STEREO);
		lame_set_num_channels(lameState, 2);
	} else {
		lame_set_mode(lameState, MONO);
		lame_set_num_channels(lameState, 1);
	}
	lame_set_in_samplerate(lameState, settings.mFrequency);
	
	if (exportSettings.mUseVBR)
	{
		lame_set_VBR(lameState, vbr_default);
		lame_set_brate(lameState, exportSettings.mBitRate);		
	}
	else
	{
		lame_set_VBR(lameState, vbr_off);
		lame_set_brate(lameState, exportSettings.mBitRate);		
	}

	int lameQuality = (int) ((1.0f - exportSettings.mQuality) * 9.0f);
	lame_set_quality(lameState, lameQuality);

	id3tag_init(lameState);
	id3tag_add_v2(lameState);
	id3tag_set_title(lameState, [title cStringUsingEncoding:NSISOLatin1StringEncoding]);
	id3tag_set_artist(lameState, [author cStringUsingEncoding:NSISOLatin1StringEncoding]);

	NSString *album = @"";
	if ([player isCurrentTuneMod]) {
		const char *fmt = [player getCurrentFormat];
		NSString *fmtStr = (fmt && strlen(fmt) > 0) ? [NSString stringWithUTF8String:fmt] : @"Amiga Tracker Module";
		album = [NSString stringWithFormat:@"Amiga Module (%@)", fmtStr];
	} else {
		album = (releaseInfo.length > 0) ? releaseInfo : @"Commodore 64 SID";
	}
	id3tag_set_album(lameState, [album cStringUsingEncoding:NSISOLatin1StringEncoding]);
	id3tag_set_track(lameState, [[NSString stringWithFormat:@"%d", [exportItem subtune]] cStringUsingEncoding:NSISOLatin1StringEncoding]);

	if (releaseInfo.length >= 4)
	{
		NSString* year = [releaseInfo substringWithRange:NSMakeRange(0, 4)];
		id3tag_set_year(lameState, [year cStringUsingEncoding:NSISOLatin1StringEncoding]);
	}
	
	id3tag_set_genre(lameState, [player isCurrentTuneMod] ? "Amiga Module" : "Chiptune");
	id3tag_set_comment(lameState, "Exported with SIDPLAY 5 for Mac");

	// Embed Retro Cover Art in MP3 ID3v2 APIC frame
	NSString *chipName = @"MOS 6581";
	if ([player isCurrentTuneMod]) {
		chipName = @"PAULA 8364";
	} else {
		const char *rawChip = [player getCurrentChipModel];
		if (rawChip && strlen(rawChip) > 0) {
			chipName = [NSString stringWithUTF8String:rawChip];
		}
	}
	NSImage *coverArt = [SPNowPlayingArtworkGenerator artworkForTitle:title
															  artist:author
															   isMod:[player isCurrentTuneMod]
														   chipModel:chipName
															 subtune:[exportItem subtune]
														subtuneCount:[player getSubtuneCount]
																size:CGSizeMake(600, 600)];
	if (coverArt) {
		CGImageRef cgRef = [coverArt CGImageForProposedRect:NULL context:nil hints:nil];
		if (cgRef) {
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
			NSData *jpegData = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @(0.85f)}];
			if (jpegData && jpegData.length > 0) {
				id3tag_set_albumart(lameState, (const char *)jpegData.bytes, jpegData.length);
			}
		}
	}
	
	int rc = lame_init_params(lameState);

	const int maxSamplesPerSlice = 64 * 1024;
	const int fadeTimeInSamples = exportSettings.mFadeOutTime * settings.mFrequency;

	UInt32 renderBufferSize = (maxSamplesPerSlice * sizeof(short) * channels);
    
    char* renderBuffer = malloc(sizeof(char)*renderBufferSize);
    if (renderBuffer == nil)
        return;
    int mp3BufferSize = (int) (1.25f * maxSamplesPerSlice * channels + 7200);
    
    unsigned char* mp3Buffer = malloc(sizeof(unsigned char)*mp3BufferSize);

	while (!exportStopped)
	{
        if (samplesRemaining == 0)
			break;

		// progress update
		NSNumber* progress = @((float)samplesCompleted / (float)(samplesCompleted + samplesRemaining));
		[self performSelectorOnMainThread:@selector(exportInProgressNotification:) withObject:progress waitUntilDone:NO];
		
		UInt32 numSamplesThisSlice = (int)samplesRemaining;
		if (numSamplesThisSlice > maxSamplesPerSlice)
			numSamplesThisSlice = maxSamplesPerSlice;

		// write it to the file
		if (numSamplesThisSlice > 0)
		{
			UInt32 sliceBytes = numSamplesThisSlice * sizeof(short) * channels;
            [player fillBuffer:renderBuffer withLen:sliceBytes];

			if (exportSettings.mWithFadeOut && (samplesRemaining - numSamplesThisSlice) < fadeTimeInSamples)
			{
				short* sampleBuffer = (short*) renderBuffer;
				
				for(int i = 0; i < numSamplesThisSlice; i++)
				{
					if ((samplesRemaining - i) < fadeTimeInSamples)
					{
						float fadeOutFactor = (float)(samplesRemaining - i) / (float)(fadeTimeInSamples);
						for (int c = 0; c < channels; c++) {
							sampleBuffer[i * channels + c] = (short)(fadeOutFactor * sampleBuffer[i * channels + c]);
						}
					}
				}
			}

			if (channels == 2) {
				rc = lame_encode_buffer_interleaved(lameState, (short int*)renderBuffer, numSamplesThisSlice, mp3Buffer, mp3BufferSize);
			} else {
				rc = lame_encode_buffer(lameState, (short int*)renderBuffer, (short int*)renderBuffer, numSamplesThisSlice, mp3Buffer, mp3BufferSize);
			}
			if (rc > 0)
				fwrite(mp3Buffer, 1, rc, outputFileHandle);
		}
		
		samplesRemaining -= numSamplesThisSlice;
		samplesCompleted += numSamplesThisSlice;
    }

	rc = lame_encode_flush(lameState, mp3Buffer, mp3BufferSize);
	fwrite(mp3Buffer, 1, rc, outputFileHandle);
	lame_close(lameState);

	free (renderBuffer);
	free (mp3Buffer);
		
    if (outputFileHandle != NULL)
		fclose(outputFileHandle);

	if (coverArt) {
		[[NSWorkspace sharedWorkspace] setIcon:coverArt forFile:destinationPath options:0];
		[self performSelectorOnMainThread:@selector(setFileIcon:) withObject:coverArt waitUntilDone:NO];
	}
 	
	//NSLog(@"file written using lame!\n");
	
	[self performSelectorOnMainThread:@selector(exportCompletedNotification:)
                                                withObject:(id)[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]
												waitUntilDone:NO];
	
}


// ----------------------------------------------------------------------------
- (void) exportCompletedNotification:(NSError *)error
// ----------------------------------------------------------------------------
{
	//NSLog(@"export stopped with error: %@\n", error);

	exportInProgress = NO;
	[self setExportStopped:YES];
	[controller exportFinished:self];
}


// ----------------------------------------------------------------------------
- (void) exportInProgressNotification:(id)progress
// ----------------------------------------------------------------------------
{
	[self setExportProgress:[progress floatValue]];
}


@end



@implementation SPExportItem

// ----------------------------------------------------------------------------
- (instancetype) init
// ----------------------------------------------------------------------------
{
    return [self initWithPath:nil andTitle:nil andAuthor:nil andSubtune:0 andLoopCount:0];
}
// ----------------------------------------------------------------------------
- (instancetype) initWithPath:(NSString*)filePath andTitle:(NSString*)titleString andAuthor:(NSString*)authorString andSubtune:(int)subtuneIndex andLoopCount:(int)loops
// ----------------------------------------------------------------------------
{
	self = [super init];
	if (self != nil)
	{
		path = filePath;
		title = titleString;
		author = authorString;
		subtune = subtuneIndex;
		loopCount = loops;
		exporter = nil;
	}
	return self;
}


// ----------------------------------------------------------------------------
- (NSString*) path
// ----------------------------------------------------------------------------
{
	return path;
}


// ----------------------------------------------------------------------------
- (void) setPath:(NSString*)filePath
// ----------------------------------------------------------------------------
{
	path = filePath;
}


// ----------------------------------------------------------------------------
- (NSString*) title
// ----------------------------------------------------------------------------
{
	return title;
}


// ----------------------------------------------------------------------------
- (void) setTitle:(NSString*)titleString
// ----------------------------------------------------------------------------
{
	title = titleString;
}


// ----------------------------------------------------------------------------
- (NSString*) author
// ----------------------------------------------------------------------------
{
	return author;
}


// ----------------------------------------------------------------------------
- (void) setAuthor:(NSString*)authorString
// ----------------------------------------------------------------------------
{
	author = authorString;
}


// ----------------------------------------------------------------------------
- (int) subtune
// ----------------------------------------------------------------------------
{
	return subtune;
}


// ----------------------------------------------------------------------------
- (void) setSubtune:(int)subtuneIndex
// ----------------------------------------------------------------------------
{
	subtune = subtuneIndex;
}


// ----------------------------------------------------------------------------
- (int) loopCount
// ----------------------------------------------------------------------------
{
	return loopCount;
}


// ----------------------------------------------------------------------------
- (void) setLoopCount:(int)loops
// ----------------------------------------------------------------------------
{
	loopCount = loops;
}


// ----------------------------------------------------------------------------
- (SPExporter*) exporter
// ----------------------------------------------------------------------------
{
	return exporter;
}


// ----------------------------------------------------------------------------
- (void) setExporter:(SPExporter*)theExporter
// ----------------------------------------------------------------------------
{
	exporter = theExporter;
}
@end

@implementation ExportSettings
@synthesize     mFileType;
@synthesize         mTimeInSeconds;
@synthesize             mWithFadeOut;
@synthesize                 mFadeOutTime;
@synthesize                 mBitRate;
@synthesize             mUseVBR;
@synthesize             mQuality;

@synthesize             mBlankScreen;
@synthesize             mIncludeStilComment;
@synthesize             mCompressOutputFile;
- (id) init
{
    self = [super init];
    mTimeInSeconds = 180;
    mWithFadeOut = NO;
    mFadeOutTime = 3;
    mBitRate = 128;
    mUseVBR = NO;
    mQuality = 0.5f;

    mBlankScreen = NO;
    mIncludeStilComment = NO;
    mCompressOutputFile = NO;
    return self;
}
@end
