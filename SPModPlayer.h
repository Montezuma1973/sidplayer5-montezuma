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

+ (BOOL) isKnownModExtension:(NSString*)ext;
+ (BOOL) isModFile:(NSString*)path;
+ (BOOL) isModData:(NSData*)data;
+ (BOOL) getModInfoForPath:(NSString*)path title:(NSString* _Nullable * _Nullable)outTitle format:(NSString* _Nullable * _Nullable)outFormat;
+ (BOOL) getModInfoForPath:(NSString*)path
                     title:(NSString* _Nullable * _Nullable)outTitle
                    format:(NSString* _Nullable * _Nullable)outFormat
                  subtunes:(int* _Nullable)outSubtunes
                    length:(int* _Nullable)outLength
                forSubtune:(int)subtuneIndex;
+ (int) getModLengthForPath:(NSString*)path andSubtune:(int)subtuneIndex;

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
- (void) seekToSeconds:(int)seconds;
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
- (int) numChannels;
- (BOOL) isVoiceSoloed:(int)voice;
- (void) toggleVoiceSoloed:(int)voice;
- (void) unmuteAllVoices;
- (float) voiceVUPeakForVoice:(int)voice;
- (NSString*) channelNoteForVoice:(int)voice;
- (NSString*) channelInstrumentForVoice:(int)voice;
- (int) channelPeriodForVoice:(int)voice;
- (int) currentPattern;
- (int) currentRow;
- (int) numRowsInCurrentPattern;
- (int) currentOrder;
- (int) currentBPM;
- (int) currentSpeed;
- (int) channelMidiNoteForVoice:(int)voice;
- (int) channelVolumeForVoice:(int)voice;
- (NSString*) channelEffectForVoice:(int)voice;
- (void) getTrackerCellForChannel:(int)ch row:(int)row note:(NSString* _Nonnull * _Nonnull)outNote ins:(NSString* _Nonnull * _Nonnull)outIns vol:(NSString* _Nonnull * _Nonnull)outVol fx:(NSString* _Nonnull * _Nonnull)outFx;

- (void) fillSidRegisterFrame:(struct SidRegisterFrame*)frame;

@end

NS_ASSUME_NONNULL_END
