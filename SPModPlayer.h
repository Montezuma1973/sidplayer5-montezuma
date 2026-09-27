//
//  SPModPlayer.h
//  SIDPLAY
//
//  Created for Amiga MOD / Tracker module support.
//

#import <Foundation/Foundation.h>
#include "PlaybackSettings.h"
#include "PlayerLibSidplayWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPModPlayer : NSObject

+ (BOOL) isModFile:(NSString*)path;
+ (BOOL) isModData:(NSData*)data;

- (BOOL) loadTuneByPath:(NSString*)path sampleRate:(int)sampleRate;
- (BOOL) loadTuneFromBuffer:(const char*)buffer withLength:(int)length sampleRate:(int)sampleRate;

- (void) startPlayback;
- (void) pausePlayback;
- (void) resumePlayback;
- (void) stopPlayback;
- (BOOL) isPlaying;

- (void) fillBuffer:(void*)buffer withLen:(int)len;

- (int) getPlaybackSeconds;
- (int) getTotalTimeSeconds;
- (int) getSubtuneCount;
- (int) getCurrentSubtune;
- (BOOL) startSubtune:(int)which;
- (BOOL) startNextSubtune;
- (BOOL) startPrevSubtune;

- (const char*) getCurrentTitle;
- (const char*) getCurrentAuthor;
- (const char*) getCurrentReleaseInfo;
- (const char*) getCurrentFormat;

- (const short*) voiceScopeBufferForVoice:(int)voice;
- (unsigned int) voiceScopeBufferSize;
- (unsigned int) voiceScopeWriteIndex;

- (float) voiceVolumeForVoice:(int)voice;
- (float) voicePreMuteVolumeForVoice:(int)voice;
- (BOOL) isVoiceMuted:(int)voice;
- (void) setVoiceMuted:(BOOL)muted forVoice:(int)voice;
- (void) toggleVoiceMuted:(int)voice;
- (void) setVoiceVolume:(float)volume forVoice:(int)voice;

- (void) fillSidRegisterFrame:(struct SidRegisterFrame*)frame;

@end

NS_ASSUME_NONNULL_END
