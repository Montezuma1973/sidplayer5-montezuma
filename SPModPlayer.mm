//
//  SPModPlayer.mm
//  SIDPLAY
//
//  Created for Amiga MOD / Tracker module support.
//

#import "SPModPlayer.h"
#include "xmp.h"
#include "SPSidNoteUtils.h"

static const unsigned int kModScopeBufferSize = 2048;

@interface SPModPlayer () {
    xmp_context mCtx;
    int mSampleRate;
    int mNumChannels;
    int mSubtuneCount;
    int mCurrentSubtune;
    int mCurrentTimeMs;
    int mTotalTimeMs;
    BOOL mIsPlaying;
    BOOL mIsLoaded;
    
    char mTitle[XMP_NAME_SIZE + 64];
    char mAuthor[64];
    char mReleaseInfo[XMP_NAME_SIZE + 64];
    char mFormat[XMP_NAME_SIZE + 64];
    
    short mScopeBuffers[4][kModScopeBufferSize];
    unsigned int mScopeWriteIndex;
    
    float mVoiceVolume[4];
    float mVoicePreMute[4];
    BOOL mVoiceMuted[4];
}
@end

@implementation SPModPlayer

static inline BOOL IsKnownModExtension(NSString* ext)
{
    if (!ext) return NO;
    return ([ext isEqualToString:@"mod"] || [ext isEqualToString:@"xm"]  ||
            [ext isEqualToString:@"s3m"] || [ext isEqualToString:@"it"]  ||
            [ext isEqualToString:@"mtm"] || [ext isEqualToString:@"ft1"] ||
            [ext isEqualToString:@"ft"]  || [ext isEqualToString:@"med"] ||
            [ext isEqualToString:@"okt"] || [ext isEqualToString:@"stm"] ||
            [ext isEqualToString:@"669"] || [ext isEqualToString:@"far"] ||
            [ext isEqualToString:@"ult"]);
}

+ (BOOL) isModFile:(NSString*)path
{
    if (!path || path.length == 0)
        return NO;
    
    NSString* ext = [path.pathExtension lowercaseString];
    if (IsKnownModExtension(ext))
    {
        return YES;
    }
    
    struct xmp_test_info ti;
    return (xmp_test_module([path fileSystemRepresentation], &ti) == 0);
}

+ (BOOL) isModData:(NSData*)data
{
    if (!data || data.length < 4)
        return NO;
    struct xmp_test_info ti;
    return (xmp_test_module_from_memory(data.bytes, (long)data.length, &ti) == 0);
}

+ (BOOL) getModInfoForPath:(NSString*)path
                     title:(NSString**)outTitle
                    format:(NSString**)outFormat
                  subtunes:(int*)outSubtunes
                    length:(int*)outLength
                forSubtune:(int)subtuneIndex
{
    if (!path || path.length == 0)
        return NO;
    
    NSString* ext = [path.pathExtension lowercaseString];
    BOOL knownExt = IsKnownModExtension(ext);
    
    struct xmp_test_info ti;
    if (!knownExt && xmp_test_module([path fileSystemRepresentation], &ti) != 0)
    {
        return NO;
    }
    
    xmp_context ctx = xmp_create_context();
    if (!ctx)
    {
        if (knownExt) {
            if (outTitle) *outTitle = [[path lastPathComponent] stringByDeletingPathExtension];
            if (outFormat) *outFormat = [ext uppercaseString];
            if (outSubtunes) *outSubtunes = 1;
            if (outLength) *outLength = 0;
            return YES;
        }
        return NO;
    }
    
    if (xmp_load_module(ctx, (char*)[path fileSystemRepresentation]) == 0)
    {
        struct xmp_module_info mi;
        xmp_get_module_info(ctx, &mi);
        
        if (outTitle) {
            NSString* t = nil;
            if (mi.mod && mi.mod->name[0] != '\0') {
                t = [NSString stringWithCString:mi.mod->name encoding:NSISOLatin1StringEncoding];
            }
            if (!t || [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
                t = [[path lastPathComponent] stringByDeletingPathExtension];
            }
            *outTitle = t;
        }
        
        if (outFormat) {
            NSString* f = nil;
            if (mi.mod && mi.mod->type[0] != '\0') {
                f = [NSString stringWithCString:mi.mod->type encoding:NSISOLatin1StringEncoding];
            }
            if (!f || f.length == 0) {
                f = [ext uppercaseString];
            }
            *outFormat = f;
        }
        
        int numSeq = (mi.num_sequences > 0) ? mi.num_sequences : 1;
        if (outSubtunes) {
            *outSubtunes = numSeq;
        }
        
        if (outLength) {
            int durationMs = 0;
            int targetSubtune = (subtuneIndex >= 1 && subtuneIndex <= numSeq) ? subtuneIndex : 1;
            if (mi.seq_data != NULL && numSeq > 0) {
                durationMs = mi.seq_data[targetSubtune - 1].duration;
            }
            
            if (durationMs <= 0) {
                if (xmp_start_player(ctx, 44100, 0) == 0) {
                    if (targetSubtune > 1) {
                        xmp_set_position(ctx, targetSubtune - 1);
                    }
                    struct xmp_frame_info fi;
                    xmp_get_frame_info(ctx, &fi);
                    durationMs = fi.total_time;
                    xmp_end_player(ctx);
                }
            }
            
            *outLength = (durationMs + 500) / 1000;
        }
        
        xmp_release_module(ctx);
        xmp_free_context(ctx);
        return YES;
    }
    
    xmp_free_context(ctx);
    
    if (knownExt) {
        if (outTitle) *outTitle = [[path lastPathComponent] stringByDeletingPathExtension];
        if (outFormat) *outFormat = [ext uppercaseString];
        if (outSubtunes) *outSubtunes = 1;
        if (outLength) *outLength = 0;
        return YES;
    }
    
    return NO;
}

+ (BOOL) getModInfoForPath:(NSString*)path title:(NSString**)outTitle format:(NSString**)outFormat
{
    return [self getModInfoForPath:path title:outTitle format:outFormat subtunes:NULL length:NULL forSubtune:1];
}

+ (int) getModLengthForPath:(NSString*)path andSubtune:(int)subtuneIndex
{
    int length = 0;
    if ([self getModInfoForPath:path title:NULL format:NULL subtunes:NULL length:&length forSubtune:subtuneIndex]) {
        return length;
    }
    return 0;
}

- (instancetype) init
{
    self = [super init];
    if (self) {
        mCtx = NULL;
        mSampleRate = 48000;
        mNumChannels = 4;
        mSubtuneCount = 1;
        mCurrentSubtune = 1;
        mCurrentTimeMs = 0;
        mTotalTimeMs = 0;
        mIsPlaying = NO;
        mIsLoaded = NO;
        mScopeWriteIndex = 0;
        
        memset(mTitle, 0, sizeof(mTitle));
        memset(mAuthor, 0, sizeof(mAuthor));
        memset(mReleaseInfo, 0, sizeof(mReleaseInfo));
        memset(mFormat, 0, sizeof(mFormat));
        memset(mScopeBuffers, 0, sizeof(mScopeBuffers));
        
        for (int i = 0; i < 4; i++) {
            mVoiceVolume[i] = 1.0f;
            mVoicePreMute[i] = 1.0f;
            mVoiceMuted[i] = NO;
        }
    }
    return self;
}

- (void) dealloc
{
    [self cleanup];
}

- (void) cleanup
{
    if (mCtx) {
        xmp_end_player(mCtx);
        xmp_release_module(mCtx);
        xmp_free_context(mCtx);
        mCtx = NULL;
    }
    mIsLoaded = NO;
    mIsPlaying = NO;
    mCurrentTimeMs = 0;
    mTotalTimeMs = 0;
}

- (BOOL) setupPlayerWithSampleRate:(int)sampleRate defaultTitle:(NSString*)defaultTitle
{
    mSampleRate = sampleRate > 0 ? sampleRate : 48000;
    if (xmp_start_player(mCtx, mSampleRate, XMP_FORMAT_MONO) != 0) {
        [self cleanup];
        return NO;
    }
    
    struct xmp_module_info mi;
    xmp_get_module_info(mCtx, &mi);
    
    mNumChannels = (mi.mod && mi.mod->chn > 0) ? mi.mod->chn : 4;
    mSubtuneCount = mi.num_sequences > 0 ? mi.num_sequences : 1;
    mCurrentSubtune = 1;
    
    if (mi.mod && mi.mod->name[0] != '\0') {
        snprintf(mTitle, sizeof(mTitle), "%s", mi.mod->name);
    } else {
        snprintf(mTitle, sizeof(mTitle), "%s", [defaultTitle UTF8String] ?: "Amiga Module");
    }
    
    snprintf(mAuthor, sizeof(mAuthor), "Amiga Tracker");
    
    if (mi.mod && mi.mod->type[0] != '\0') {
        snprintf(mFormat, sizeof(mFormat), "%s", mi.mod->type);
        snprintf(mReleaseInfo, sizeof(mReleaseInfo), "%s (%d ch)", mi.mod->type, mNumChannels);
    } else {
        snprintf(mFormat, sizeof(mFormat), "Amiga MOD");
        snprintf(mReleaseInfo, sizeof(mReleaseInfo), "Amiga MOD (%d ch)", mNumChannels);
    }
    
    struct xmp_frame_info fi;
    xmp_get_frame_info(mCtx, &fi);
    mTotalTimeMs = fi.total_time;
    mCurrentTimeMs = 0;
    
    for (int i = 0; i < 4; i++) {
        mVoiceVolume[i] = 1.0f;
        mVoicePreMute[i] = 1.0f;
        mVoiceMuted[i] = NO;
        xmp_channel_mute(mCtx, i, 0);
        xmp_channel_vol(mCtx, i, 100);
    }
    
    mIsLoaded = YES;
    mIsPlaying = NO;
    return YES;
}

- (BOOL) loadTuneByPath:(NSString*)path sampleRate:(int)sampleRate
{
    [self cleanup];
    
    mCtx = xmp_create_context();
    if (!mCtx)
        return NO;
    
    if (xmp_load_module(mCtx, (char*)[path fileSystemRepresentation]) != 0) {
        xmp_free_context(mCtx);
        mCtx = NULL;
        return NO;
    }
    
    return [self setupPlayerWithSampleRate:sampleRate defaultTitle:path.lastPathComponent.stringByDeletingPathExtension];
}

- (BOOL) loadTuneFromBuffer:(const char*)buffer withLength:(int)length sampleRate:(int)sampleRate
{
    [self cleanup];
    
    if (!buffer || length <= 0)
        return NO;
    
    mCtx = xmp_create_context();
    if (!mCtx)
        return NO;
    
    if (xmp_load_module_from_memory(mCtx, buffer, (long)length) != 0) {
        xmp_free_context(mCtx);
        mCtx = NULL;
        return NO;
    }
    
    return [self setupPlayerWithSampleRate:sampleRate defaultTitle:@"Amiga Module"];
}

- (void) startPlayback
{
    if (mIsLoaded && mCtx) {
        mIsPlaying = YES;
    }
}

- (void) pausePlayback
{
    mIsPlaying = NO;
}

- (void) resumePlayback
{
    if (mIsLoaded && mCtx) {
        mIsPlaying = YES;
    }
}

- (void) stopPlayback
{
    mIsPlaying = NO;
    if (mCtx) {
        xmp_seek_time(mCtx, 0);
        mCurrentTimeMs = 0;
    }
}

- (BOOL) isPlaying
{
    return mIsPlaying;
}

- (void) fillBuffer:(void*)buffer withLen:(int)len
{
    if (!mIsLoaded || !mCtx || !mIsPlaying) {
        memset(buffer, 0, len);
        return;
    }
    
    int rc = xmp_play_buffer(mCtx, buffer, len, 0);
    if (rc != 0) {
        // Module ended
        memset(buffer, 0, len);
        mIsPlaying = NO;
        return;
    }
    
    struct xmp_frame_info fi;
    xmp_get_frame_info(mCtx, &fi);
    mCurrentTimeMs = fi.time;
    mTotalTimeMs = fi.total_time;
    
    // Update oscilloscope buffers
    short* samples = (short*)buffer;
    int sampleCount = len / sizeof(short);
    for (int s = 0; s < sampleCount; s++) {
        short sample = samples[s];
        unsigned int idx = mScopeWriteIndex;
        for (int ch = 0; ch < 4 && ch < mNumChannels; ch++) {
            if (mVoiceMuted[ch]) {
                mScopeBuffers[ch][idx] = 0;
            } else {
                int vol = fi.channel_info[ch].volume; // 0..64
                mScopeBuffers[ch][idx] = (short)((sample * vol) / 64);
            }
        }
        mScopeWriteIndex = (idx + 1) % kModScopeBufferSize;
    }
}

- (int) getPlaybackSeconds
{
    return mCurrentTimeMs / 1000;
}

- (int) getTotalTimeSeconds
{
    return mTotalTimeMs / 1000;
}

- (int) getSubtuneCount
{
    return mSubtuneCount;
}

- (int) getCurrentSubtune
{
    return mCurrentSubtune;
}

- (BOOL) startSubtune:(int)which
{
    if (!mCtx || which < 1 || which > mSubtuneCount)
        return NO;
    mCurrentSubtune = which;
    xmp_set_position(mCtx, which - 1);
    struct xmp_frame_info fi;
    xmp_get_frame_info(mCtx, &fi);
    mTotalTimeMs = fi.total_time;
    struct xmp_module_info mi;
    xmp_get_module_info(mCtx, &mi);
    if (mTotalTimeMs <= 0 && mi.seq_data != NULL && which <= mi.num_sequences) {
        mTotalTimeMs = mi.seq_data[which - 1].duration;
    }
    mCurrentTimeMs = 0;
    return YES;
}

- (BOOL) startNextSubtune
{
    if (mCurrentSubtune < mSubtuneCount) {
        return [self startSubtune:mCurrentSubtune + 1];
    }
    return YES;
}

- (BOOL) startPrevSubtune
{
    if (mCurrentSubtune > 1) {
        return [self startSubtune:mCurrentSubtune - 1];
    }
    return YES;
}

- (const char*) getCurrentTitle       { return mTitle; }
- (const char*) getCurrentAuthor      { return mAuthor; }
- (const char*) getCurrentReleaseInfo { return mReleaseInfo; }
- (const char*) getCurrentFormat      { return mFormat; }

- (const short*) voiceScopeBufferForVoice:(int)voice
{
    if (voice < 0 || voice >= 4) return NULL;
    return mScopeBuffers[voice];
}

- (unsigned int) voiceScopeBufferSize
{
    return kModScopeBufferSize;
}

- (unsigned int) voiceScopeWriteIndex
{
    return mScopeWriteIndex;
}

- (float) voiceVolumeForVoice:(int)voice
{
    if (voice < 0 || voice >= 4) return 0.0f;
    return mVoiceVolume[voice];
}

- (float) voicePreMuteVolumeForVoice:(int)voice
{
    if (voice < 0 || voice >= 4) return 0.0f;
    return mVoicePreMute[voice];
}

- (BOOL) isVoiceMuted:(int)voice
{
    if (voice < 0 || voice >= 4) return NO;
    return mVoiceMuted[voice];
}

- (void) setVoiceMuted:(BOOL)muted forVoice:(int)voice
{
    if (voice < 0 || voice >= 4) return;
    mVoiceMuted[voice] = muted;
    if (mCtx) {
        xmp_channel_mute(mCtx, voice, muted ? 1 : 0);
    }
    if (muted) {
        mVoicePreMute[voice] = mVoiceVolume[voice];
        [self setVoiceVolume:0.0f forVoice:voice];
    } else {
        [self setVoiceVolume:mVoicePreMute[voice] forVoice:voice];
    }
}

- (void) toggleVoiceMuted:(int)voice
{
    [self setVoiceMuted:![self isVoiceMuted:voice] forVoice:voice];
}

- (void) setVoiceVolume:(float)volume forVoice:(int)voice
{
    if (voice < 0 || voice >= 4) return;
    mVoiceVolume[voice] = volume;
    if (!mVoiceMuted[voice]) {
        mVoicePreMute[voice] = volume;
    }
    if (mCtx) {
        xmp_channel_vol(mCtx, voice, (int)(volume * 100.0f));
    }
}

- (void) fillSidRegisterFrame:(struct SidRegisterFrame*)frame
{
    if (!frame) return;
    memset(frame->mRegisters, 0, sizeof(frame->mRegisters));
    if (!mIsLoaded || !mCtx || !mIsPlaying) return;
    
    struct xmp_frame_info fi;
    xmp_get_frame_info(mCtx, &fi);
    
    for (int i = 0; i < 3 && i < mNumChannels; i++) {
        int regOffset = i * 7;
        int vol = fi.channel_info[i].volume; // 0..64
        int note = fi.channel_info[i].note;   // 1..120
        if (vol > 0 && note > 0 && !mVoiceMuted[i]) {
            int noteIdx = note - 1; // 0 = C-1
            if (noteIdx >= 0 && noteIdx < sSPSidNoteCount) {
                uint16_t freq = sSPSidNoteMap[noteIdx].frequency;
                frame->mRegisters[regOffset] = freq & 0xFF;
                frame->mRegisters[regOffset + 1] = (freq >> 8) & 0xFF;
            }
            frame->mRegisters[regOffset + 4] = 0x21; // Sawtooth + Gate ON
            frame->mRegisters[regOffset + 6] = (uint8_t)((vol >> 2) << 4);
        } else {
            frame->mRegisters[regOffset + 4] = 0x00; // Gate OFF
        }
    }
}

@end
