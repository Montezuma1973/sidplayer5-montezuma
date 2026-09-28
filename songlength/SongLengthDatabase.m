#import "SongLengthDatabase.h"
#import "SidTuneWrapper.h"
#import "SPPlayerWindow.h"
#import "SPPreferencesController.h"

#include "SongLength.h"
#include "Item.h"

static NSString* SidplaySongLengthDataBaseRelativePath = @"DOCUMENTS/Songlengths.txt";
static NSString* SidplaySongLengthDataBaseRelativePathNewMD5 = @"DOCUMENTS/Songlengths.md5";

static SongLengthDatabase* sharedInstance = nil;

@implementation SongLengthDatabase
@synthesize databaseAvailable;

// ----------------------------------------------------------------------------
+ (SongLengthDatabase*) sharedInstance
// ----------------------------------------------------------------------------
{
	if (sharedInstance == nil || ![sharedInstance databaseAvailable])
	{
		if (gPreferences && gPreferences.mCollections)
		{
			for (NSString* colPath in gPreferences.mCollections)
			{
				SongLengthDatabase* db = [[SongLengthDatabase alloc] initWithRootPath:colPath];
				if (db != nil && [db databaseAvailable])
				{
					sharedInstance = db;
					break;
				}
			}
		}
	}
	return sharedInstance;
}


// ----------------------------------------------------------------------------
+ (void) setSharedInstance:(SongLengthDatabase*)database;
// ----------------------------------------------------------------------------
{
	if (database != nil && [database databaseAvailable])
	{
		sharedInstance = database;
	}
}

// ----------------------------------------------------------------------------
- (instancetype) init
// ----------------------------------------------------------------------------
{
    self = [super init];
    if (self != nil)
    {
        databaseAvailable = NO;
        newMD5FormatUsed = NO;
        songLength = nil;
    }
    return self;
}

// ----------------------------------------------------------------------------
- (instancetype) initWithRootPath:(NSString*)rootPath
// ----------------------------------------------------------------------------
{
	self = [super init];
	if (self != nil)
	{
		databaseAvailable = NO;
		newMD5FormatUsed = NO;
		if (rootPath == nil || rootPath.length == 0)
			return nil;

		// 1. Check rootPath and walk up parent directories (up to 6 levels)
		NSString* searchDir = rootPath;
		for (int level = 0; level < 6; level++)
		{
			NSString* md5Path = [searchDir stringByAppendingPathComponent:SidplaySongLengthDataBaseRelativePathNewMD5];
			if ([[NSFileManager defaultManager] fileExistsAtPath:md5Path])
			{
				newMD5db = [[NewMD5SongLengthDatabase alloc] initWithPath:md5Path];
				if ([newMD5db validDatabase])
				{
					databasePath = md5Path;
					collectionRootPath = searchDir;
					newMD5FormatUsed = YES;
					databaseAvailable = YES;
					return self;
				}
			}
			
			NSString* txtPath = [searchDir stringByAppendingPathComponent:SidplaySongLengthDataBaseRelativePath];
			if ([[NSFileManager defaultManager] fileExistsAtPath:txtPath])
			{
				songLength = [[SongLength alloc] initWithFile:[txtPath cStringUsingEncoding:NSUTF8StringEncoding]];
				if ([songLength isAvailable])
				{
					databasePath = txtPath;
					collectionRootPath = searchDir;
					databaseAvailable = YES;
					return self;
				}
			}
			
			NSString* parentDir = [searchDir stringByDeletingLastPathComponent];
			if ([parentDir isEqualToString:searchDir] || parentDir.length == 0)
				break;
			searchDir = parentDir;
		}

		// 2. Fallback: check all collections in gPreferences.mCollections
		if (gPreferences && gPreferences.mCollections)
		{
			for (NSString* colPath in gPreferences.mCollections)
			{
				NSString* md5Path = [colPath stringByAppendingPathComponent:SidplaySongLengthDataBaseRelativePathNewMD5];
				if ([[NSFileManager defaultManager] fileExistsAtPath:md5Path])
				{
					newMD5db = [[NewMD5SongLengthDatabase alloc] initWithPath:md5Path];
					if ([newMD5db validDatabase])
					{
						databasePath = md5Path;
						collectionRootPath = colPath;
						newMD5FormatUsed = YES;
						databaseAvailable = YES;
						return self;
					}
				}
			}
		}
	}
    return nil;
}

// ----------------------------------------------------------------------------
- (int) getSongLengthByPath:(NSString*)path andSubtune:(int)subtune
// ----------------------------------------------------------------------------
{
    if (!databaseAvailable)
		return 0;
	
	if (path == nil)
		return 0;
    if (!newMD5FormatUsed) {
        struct SongLengthDBitem item;
        item.playtime = 0;
       
 
        if ([songLength isAvailable]) {
            bool success = [songLength getItem:[collectionRootPath cStringUsingEncoding:NSUTF8StringEncoding]
                                          file:[path cStringUsingEncoding:NSUTF8StringEncoding]
                                          song:subtune item:&item];
            
            if (success)
                return item.playtime;
        }
    } else {
        return [newMD5db getSongLengthByPath:path andSubtune:subtune];
    }
    return 0;
}

// ----------------------------------------------------------------------------
- (int) getSongLengthFromBuffer:(void*)buffer withBufferLength:(int)length andSubtune:(int)subtune
// ----------------------------------------------------------------------------
{
    if (!newMD5FormatUsed) {
        SidTuneWrapper* sidtune = [[SidTuneWrapper alloc] init];
        [sidtune load:buffer withLength:length];
        return [self getSongLengthFromSidTune:sidtune andSubtune:subtune];
    } else {
        return [newMD5db getSongLengthFromBuffer:buffer withBufferLength:length andSubtune:subtune];
    }
}


// ----------------------------------------------------------------------------
- (int) getSongLengthFromSidTune:(SidTuneWrapper*)sidtune andSubtune:(int)subtune
// ----------------------------------------------------------------------------
{
	if (!databaseAvailable)
		return 0;

    struct SongLengthDBitem item;
    bool success = [songLength getItem:sidtune number:subtune item:&item];

	if (success)
		return item.playtime;

	return 0;
}


// ----------------------------------------------------------------------------
- (NSString*) databasePath
// ----------------------------------------------------------------------------
{
	return databasePath;
}


@end
