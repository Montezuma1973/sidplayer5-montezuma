#import "SPBrowserItem.h"
#import "SongLengthDatabase.h"
#import "SPCollectionUtilities.h"
#import "SPPlaylist.h"
#import "SPPlaylistItem.h"
#import "SPModPlayer.h"
#import "SPPreferencesController.h"


@implementation SPBrowserItem
// ----------------------------------------------------------------------------
- (instancetype) init
// ----------------------------------------------------------------------------
{
    return [self initWithPath:nil isFolder:NO forParent:nil withDefaultSubtune:0];
}
// ----------------------------------------------------------------------------
- (instancetype) initWithPath:(NSString*)thePath isFolder:(BOOL)folder forParent:(SPBrowserItem*)parentItem withDefaultSubtune:(NSInteger)subtuneIndex
// ----------------------------------------------------------------------------
{
    if (self = [super init]) 
	{
		if (thePath == nil)
			return nil;
			
		isFolder = folder;
		path = thePath;
		children = nil;
		parent = parentItem;
		playlistIndex = 0;
		loopCount = 0;
		fileDoesNotExist = NO;
		
		if (folder)
		{
			itemType = SP_ITEM_TYPE_FOLDER;
			title = path.lastPathComponent;
			author = @"";
			releaseInfo = @"";
			
			defaultSubTune = 0;
			subTuneCount = 0;
			[self setPlayTimeInSeconds:0];
		}
		else
		{
			FILE* fileHandle = fopen([thePath fileSystemRepresentation], "rb");
			if (fileHandle == NULL)
			{
				title = @"* FILE NOT FOUND *";
				author = @"UNKNOWN";
				releaseInfo = @"UNKNOWN";
				
				defaultSubTune = 0;
				subTuneCount = 0;
				[self setPlayTimeInSeconds:0];
				
				fileDoesNotExist = YES;
			}
			else
			{
				static const int max_tunesize = 65536 + 0x7c;
				static char filebuffer[max_tunesize];
				size_t length = fread(filebuffer, 1, max_tunesize, fileHandle);
				fclose(fileHandle);

				BOOL isSid = (length >= 4) &&
				             (filebuffer[0] == 'P' || filebuffer[0] == 'R') &&
				             (filebuffer[1] == 'S' && filebuffer[2] == 'I' && filebuffer[3] == 'D');

				if (!isSid)
				{
					NSString* modTitle = nil;
					NSString* modFormat = nil;
					int modSubtunes = 1;
					int modLength = 0;
					int targetSubtune = (subtuneIndex > 0) ? (int)subtuneIndex : 1;
					if ([SPModPlayer getModInfoForPath:thePath
					                             title:&modTitle
					                            format:&modFormat
					                          subtunes:&modSubtunes
					                            length:&modLength
					                        forSubtune:targetSubtune])
					{
						itemType = SP_ITEM_TYPE_AMIGA_MOD;
						subTuneCount = (modSubtunes > 0) ? (unsigned short)modSubtunes : 1;
						defaultSubTune = (subtuneIndex > 0 && subtuneIndex <= subTuneCount) ? (unsigned short)subtuneIndex : 1;
						title = modTitle ? modTitle : [thePath.lastPathComponent stringByDeletingPathExtension];
						
						NSString* modAuthor = @"";
						if (parentItem != nil && [parentItem isFolder] && [[parentItem title] length] > 0 &&
						    ![[parentItem title] isEqualToString:@"Amiga"] && ![[parentItem title] isEqualToString:@"Mods"])
						{
							modAuthor = [parentItem title];
						}
						else
						{
							NSString* parentFolder = thePath.stringByDeletingLastPathComponent.lastPathComponent;
							if ([parentFolder caseInsensitiveCompare:@"MS-DOS"] == NSOrderedSame ||
							    [parentFolder caseInsensitiveCompare:@"Docs"] == NSOrderedSame)
							{
								parentFolder = thePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent;
							}
							if (parentFolder.length > 0 && ![parentFolder isEqualToString:@"Amiga"] && ![parentFolder isEqualToString:@"Mods"])
							{
								modAuthor = parentFolder;
							}
						}
						author = modAuthor;
						releaseInfo = modFormat ? modFormat : @"Tracker Module";
						if (modLength <= 0)
						{
							modLength = (gPreferences && gPreferences.mDefaultPlayTime > 0) ? gPreferences.mDefaultPlayTime : 180;
						}
						[self setPlayTimeInSeconds:modLength];
						return self;
					}
					else
					{
						return nil;
					}
				}

				itemType = SP_ITEM_TYPE_C64;
				subTuneCount = *(unsigned short*)(filebuffer + 0x0e);
				defaultSubTune = *(unsigned short*)(filebuffer + 0x10);

#if TARGET_RT_LITTLE_ENDIAN
				subTuneCount = Endian16_Swap(subTuneCount);
				defaultSubTune = Endian16_Swap(defaultSubTune);
#endif		
			
				if (subtuneIndex != 0)
					defaultSubTune = subtuneIndex;
			
				const int maxStringLength = 32;
				char titleBuf[maxStringLength + 1];
				memcpy(titleBuf, filebuffer + 0x16, maxStringLength);
				titleBuf[maxStringLength] = 0;
				title = [NSString stringWithCString:titleBuf encoding:NSISOLatin1StringEncoding];

				char authorBuf[maxStringLength + 1];
				memcpy(authorBuf, filebuffer + 0x36, maxStringLength);
				authorBuf[maxStringLength] = 0;
				author = [NSString stringWithCString:authorBuf encoding:NSISOLatin1StringEncoding];

				char releasedBuf[maxStringLength + 1];
				memcpy(releasedBuf, filebuffer + 0x56, maxStringLength);
				releasedBuf[maxStringLength] = 0;
				releaseInfo = [NSString stringWithCString:releasedBuf encoding:NSISOLatin1StringEncoding];
				
				int playtime = (int)[[SongLengthDatabase sharedInstance] getSongLengthFromBuffer:filebuffer withBufferLength: (int)length andSubtune:defaultSubTune];
				if (playtime <= 0)
				{
					playtime = (int)[[SongLengthDatabase sharedInstance] getSongLengthByPath:thePath andSubtune:(int)defaultSubTune];
				}
				if (playtime <= 0)
				{
					playtime = (gPreferences && gPreferences.mDefaultPlayTime > 0) ? gPreferences.mDefaultPlayTime : 180;
				}
				[self setPlayTimeInSeconds:playtime];
			}
		}
	}
	
    return self;
}


static inline BOOL IsPlayableFile(NSString* file, NSString* path)
{
	NSString* ext = file.pathExtension.lowercaseString;
	NSString* lowerFile = [file lowercaseString];
	BOOL isModPrefixed = [lowerFile hasPrefix:@"mod."] || [lowerFile hasPrefix:@"xm."] || [lowerFile hasPrefix:@"s3m."] || [lowerFile hasPrefix:@"it."] || [lowerFile hasPrefix:@"med."];
	return ([ext isEqualToString:@"sid"] || [ext isEqualToString:@"mod"] || isModPrefixed || [SPModPlayer isKnownModExtension:ext] || [SPModPlayer isModFile:path]);
}


// ----------------------------------------------------------------------------
- (instancetype) initWithMetaDataItem:(NSMetadataItem*)item
// ----------------------------------------------------------------------------
{
	NSString* thePath = [item valueForAttribute:@"kMDItemPath"];
	if (thePath == nil || thePath.length == 0)
		return nil;

	BOOL isDir = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:thePath isDirectory:&isDir] && isDir)
		return nil;

	// For Amiga MOD / Tracker files or files missing Spotlight SID metadata,
	// delegate to initWithPath: to properly inspect the file and extract title, author,
	// format, subtunes and playtime.
	if ([SPModPlayer isModFile:thePath])
	{
		return [self initWithPath:thePath isFolder:NO forParent:nil withDefaultSubtune:0];
	}

	NSString* mdTitle = [item valueForAttribute:@"kMDItemTitle"];
	NSString* mdComposer = [item valueForAttribute:@"kMDItemComposer"];
	if (mdTitle == nil || mdComposer == nil)
	{
		return [self initWithPath:thePath isFolder:NO forParent:nil withDefaultSubtune:0];
	}

    if (self = [super init]) 
	{
		isFolder = NO;
		children = nil;
		parent = nil;
		playlistIndex = 0;
		loopCount = 0;
		path = thePath;
		itemType = SP_ITEM_TYPE_C64;

		title = mdTitle;
		author = mdComposer; 
		releaseInfo = [item valueForAttribute:@"org_sidmusic_Released"]; 
		defaultSubTune = [[item valueForAttribute:@"org_sidmusic_DefaultSubtune"] integerValue]; 
		subTuneCount = [[item valueForAttribute:@"org_sidmusic_SubtuneCount"] integerValue]; 
		
		int playtime = [[SongLengthDatabase sharedInstance] getSongLengthByPath:path andSubtune:(int)defaultSubTune];
		if (playtime <= 0)
		{
			playtime = (gPreferences && gPreferences.mDefaultPlayTime > 0) ? gPreferences.mDefaultPlayTime : 180;
		}
		[self setPlayTimeInSeconds:playtime];
	}
	
	return self;
}


// ----------------------------------------------------------------------------
+ (void) fillArray:(NSMutableArray*)browserItems withDirectoryContentsAtPath:(NSString*)rootPath andParent:(SPBrowserItem*)parentItem
// ----------------------------------------------------------------------------
{
	if (rootPath == nil || rootPath.length == 0)
		return;

	NSError* error = nil;
	NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:&error];
	if (!files || error)
		return;

	for (NSString* file in files)
	{
		if (file.length == 0 || [file hasPrefix:@"."])
			continue;

		if ([file caseInsensitiveCompare:@"DOCUMENTS"] == NSOrderedSame)
			continue;

		if ([file containsString:@"_2SID"] || [file containsString:@"_3SID"])
			continue;

		NSString* path = [rootPath stringByAppendingPathComponent:file];
		BOOL folder = NO;
		BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&folder];
		if (!exists)
			continue;

		NSString* ext = file.pathExtension.lowercaseString;
		NSString* lowerFile = [file lowercaseString];
		BOOL isModPrefixed = [lowerFile hasPrefix:@"mod."] || [lowerFile hasPrefix:@"xm."] || [lowerFile hasPrefix:@"s3m."] || [lowerFile hasPrefix:@"it."] || [lowerFile hasPrefix:@"med."];
		if (folder || [ext isEqualToString:@"sid"] || [ext isEqualToString:@"mod"] || isModPrefixed || [SPModPlayer isKnownModExtension:ext] || [SPModPlayer isModFile:path])
		{
			SPBrowserItem* item = [[SPBrowserItem alloc] initWithPath:path isFolder:folder forParent:parentItem withDefaultSubtune:0];
			if (item != nil)
				[browserItems addObject:item];
		}
	}
}


// ----------------------------------------------------------------------------
+ (void) addPlayableItemsFromDirectory:(NSString*)dirPath
                               toArray:(NSMutableArray*)browserItems
                             seenPaths:(NSMutableSet*)seenPaths
                              maxDepth:(int)maxDepth
                          currentDepth:(int)currentDepth
// ----------------------------------------------------------------------------
{
	if (dirPath == nil || dirPath.length == 0 || currentDepth > maxDepth)
		return;

	NSString* dirName = dirPath.lastPathComponent;
	if ([dirName caseInsensitiveCompare:@"DOCUMENTS"] == NSOrderedSame ||
	    [dirName caseInsensitiveCompare:@"Docs"] == NSOrderedSame ||
	    [dirName hasPrefix:@"."])
	{
		return;
	}

	NSError* error = nil;
	NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
	if (!files || error)
		return;

	for (NSString* file in files)
	{
		if (file.length == 0 || [file hasPrefix:@"."])
			continue;

		if ([file caseInsensitiveCompare:@"DOCUMENTS"] == NSOrderedSame ||
		    [file caseInsensitiveCompare:@"Docs"] == NSOrderedSame)
			continue;

		if ([file containsString:@"_2SID"] || [file containsString:@"_3SID"])
			continue;

		NSString* filePath = [dirPath stringByAppendingPathComponent:file];
		BOOL folder = NO;
		BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&folder];
		if (!exists)
			continue;

		if (folder)
		{
			if (currentDepth < maxDepth)
			{
				[self addPlayableItemsFromDirectory:filePath
				                            toArray:browserItems
				                          seenPaths:seenPaths
				                           maxDepth:maxDepth
				                       currentDepth:currentDepth + 1];
			}
		}
		else
		{
			if ([seenPaths containsObject:filePath])
				continue;

			if (IsPlayableFile(file, filePath))
			{
				SPBrowserItem* item = [[SPBrowserItem alloc] initWithPath:filePath isFolder:NO forParent:nil withDefaultSubtune:0];
				if (item != nil)
				{
					[seenPaths addObject:filePath];
					[browserItems addObject:item];
				}
			}
		}
	}
}


// ----------------------------------------------------------------------------
+ (void) fillArray:(NSMutableArray*)browserItems withMetaDataQueryResults:(NSArray*)results
// ----------------------------------------------------------------------------
{
	NSMutableSet* seenPaths = [NSMutableSet setWithCapacity:results.count];
	for (id item in results)
	{
		if (![item isKindOfClass:[NSMetadataItem class]])
			continue;

		NSMetadataItem* mdItem = (NSMetadataItem*)item;
		NSString* thePath = [mdItem valueForAttribute:@"kMDItemPath"];
		if (thePath == nil || thePath.length == 0)
			continue;

		BOOL isDir = NO;
		if ([[NSFileManager defaultManager] fileExistsAtPath:thePath isDirectory:&isDir] && isDir)
		{
			NSString* folderName = thePath.lastPathComponent;
			if ([folderName caseInsensitiveCompare:@"Amiga"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"Mods"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"MUSICIANS"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"DEMOS"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"GAMES"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"DOCUMENTS"] == NSOrderedSame ||
			    [folderName caseInsensitiveCompare:@"Docs"] == NSOrderedSame)
			{
				continue;
			}

			[self addPlayableItemsFromDirectory:thePath
			                            toArray:browserItems
			                          seenPaths:seenPaths
			                           maxDepth:2
			                       currentDepth:0];
		}
		else
		{
			if ([seenPaths containsObject:thePath])
				continue;

			SPBrowserItem* browserItem = [[SPBrowserItem alloc] initWithMetaDataItem:mdItem];
			if (browserItem != nil)
			{
				[seenPaths addObject:thePath];
				[browserItems addObject:browserItem];
			}
		}
	}
}


// ----------------------------------------------------------------------------
+ (void) fillArray:(NSMutableArray*)browserItems withPlaylist:(SPPlaylist*)playlist
// ----------------------------------------------------------------------------
{
	for (int i = 0; i < [playlist count]; i++)
	{	
		SPPlaylistItem* playlistItem = [playlist itemAtIndex:i];
		NSString* absolutePath = [[SPCollectionUtilities sharedInstance] absolutePathFromRelativePath:[playlistItem path]];
		SPBrowserItem* browserItem = [[SPBrowserItem alloc] initWithPath:absolutePath isFolder:NO forParent:nil withDefaultSubtune:[playlistItem subtune]];
		if (browserItem != nil)
		{
			[browserItem setPlaylistIndex:i];
			[browserItem setLoopCount:[playlistItem loopCount]];
			[browserItems addObject:browserItem];
		}
	}
}


// ----------------------------------------------------------------------------
- (void) addChild:(SPBrowserItem*)item
// ----------------------------------------------------------------------------
{
	[children addObject:item];
}


// ----------------------------------------------------------------------------
- (id) childAtIndex:(int)index
// ----------------------------------------------------------------------------
{
	if (index < children.count)
		return children[index];
	else
		return nil;
}


// ----------------------------------------------------------------------------
- (BOOL) hasChildren
// ----------------------------------------------------------------------------
{
	return (children.count > 0);
}


// ----------------------------------------------------------------------------
- (NSMutableArray*) children
// ----------------------------------------------------------------------------
{
	if (children == nil && isFolder)
	{
		children = [[NSMutableArray alloc] init];
		[SPBrowserItem fillArray:children withDirectoryContentsAtPath:path andParent:self];
	}

	return children;
}


// ----------------------------------------------------------------------------
- (SPBrowserItem*) parent;
// ----------------------------------------------------------------------------
{
	return parent;
}


// ----------------------------------------------------------------------------
- (BOOL) isFolder
// ----------------------------------------------------------------------------
{
	return isFolder;
}


// ----------------------------------------------------------------------------
- (void) setIsFolder:(BOOL)flag
// ----------------------------------------------------------------------------
{
	isFolder = flag;
}

// ----------------------------------------------------------------------------
- (NSString*) title
// ----------------------------------------------------------------------------
{
	return title;
}


// ----------------------------------------------------------------------------
- (void) setTitle:(NSString*)newTitle
// ----------------------------------------------------------------------------
{
	title = newTitle;
}


// ----------------------------------------------------------------------------
- (NSString*) author
// ----------------------------------------------------------------------------
{
	return author;
}


// ----------------------------------------------------------------------------
- (void) setAuthor:(NSString*)newAuthor
// ----------------------------------------------------------------------------
{
	author = newAuthor;
}


// ----------------------------------------------------------------------------
- (NSString*) releaseInfo
// ----------------------------------------------------------------------------
{
	return releaseInfo;
}


// ----------------------------------------------------------------------------
- (void) setReleaseInfo:(NSString*)newReleaseInfo
// ----------------------------------------------------------------------------
{
	releaseInfo = newReleaseInfo;
}


// ----------------------------------------------------------------------------
- (NSString*) path
// ----------------------------------------------------------------------------
{
	return path;
}


// ----------------------------------------------------------------------------
- (void) setPath:(NSString*)newPath
// ----------------------------------------------------------------------------
{
	path = newPath;
}


// ----------------------------------------------------------------------------
- (int) playTimeInSeconds
// ----------------------------------------------------------------------------
{
	return playTimeInSeconds;
}


// ----------------------------------------------------------------------------
- (void) setPlayTimeInSeconds:(int)seconds
// ----------------------------------------------------------------------------
{
	playTimeInSeconds = seconds;
	
	playTimeMinutes = playTimeInSeconds / 60;
	playTimeSeconds = playTimeInSeconds - (playTimeMinutes * 60);
	
	if (playTimeMinutes > 99)
		playTimeMinutes = 99;

	if (playTimeSeconds > 59)
		playTimeSeconds = 59;
}


// ----------------------------------------------------------------------------
- (int) playTimeMinutes
// ----------------------------------------------------------------------------
{
	return playTimeMinutes;
}


// ----------------------------------------------------------------------------
- (int) playTimeSeconds
// ----------------------------------------------------------------------------
{
	return playTimeSeconds;
}


// ----------------------------------------------------------------------------
- (unsigned short) defaultSubTune
// ----------------------------------------------------------------------------
{
	return defaultSubTune;
}


// ----------------------------------------------------------------------------
- (void) setDefaultSubTune:(unsigned short)subtune
// ----------------------------------------------------------------------------
{
	defaultSubTune = subtune;
}


// ----------------------------------------------------------------------------
- (unsigned short) subTuneCount
// ----------------------------------------------------------------------------
{
	return subTuneCount;
}


// ----------------------------------------------------------------------------
- (void) setSubTuneCount:(unsigned short)count
// ----------------------------------------------------------------------------
{
	subTuneCount = count;
}


// ----------------------------------------------------------------------------
- (NSInteger) playlistIndex
// ----------------------------------------------------------------------------
{
	return playlistIndex;
}


// ----------------------------------------------------------------------------
- (void) setPlaylistIndex:(NSInteger)indexValue
// ----------------------------------------------------------------------------
{
	playlistIndex = indexValue;
}


// ----------------------------------------------------------------------------
- (NSInteger) loopCount
// ----------------------------------------------------------------------------
{
	return loopCount;
}


// ----------------------------------------------------------------------------
- (void) setLoopCount:(NSInteger)count
// ----------------------------------------------------------------------------
{
	loopCount = count;
}


// ----------------------------------------------------------------------------
- (BOOL) fileDoesNotExist
// ----------------------------------------------------------------------------
{
	return fileDoesNotExist;
}


// ----------------------------------------------------------------------------
- (SPItemType) itemType
// ----------------------------------------------------------------------------
{
	return itemType;
}


// ----------------------------------------------------------------------------
- (void) setItemType:(SPItemType)type
// ----------------------------------------------------------------------------
{
	itemType = type;
}


@end
