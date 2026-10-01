//
//  SPAudioProcessor.mm
//  SIDPLAY
//
//  Created for Milestone 5: Audio Engine Architecture, Headphone Crossfeed & Spatial Widener.
//

#import "SPAudioProcessor.h"
#include <atomic>
#include <cmath>

NSString * const SPAudioProcessorCrossfeedChangedNotification = @"SPAudioProcessorCrossfeedChangedNotification";
NSString * const SPAudioProcessorWidenerChangedNotification   = @"SPAudioProcessorWidenerChangedNotification";

static NSString * const kPrefKeyCrossfeedMode = @"SPAudioCrossfeedMode";
static NSString * const kPrefKeyWidenerMode   = @"SPAudioSpatialWidenerMode";

static const int kCrossfeedDelayBufferSize = 128;
static const int kWidenerDelayBufferSize   = 4096;

static inline short softClip(float sample) {
    if (sample > 32767.0f) {
        float excess = sample - 32767.0f;
        sample = 32767.0f + excess / (1.0f + excess / 8000.0f);
        if (sample > 32767.0f) sample = 32767.0f;
    } else if (sample < -32768.0f) {
        float excess = -32768.0f - sample;
        sample = -32768.0f - excess / (1.0f + excess / 8000.0f);
        if (sample < -32768.0f) sample = -32768.0f;
    }
    return (short)sample;
}

@implementation SPAudioProcessor {
    std::atomic<int> _crossfeedMode;
    std::atomic<int> _spatialWidenerMode;
    
    // Crossfeed DSP state
    float _leftLowpass;
    float _rightLowpass;
    float _crossDelayL[kCrossfeedDelayBufferSize];
    float _crossDelayR[kCrossfeedDelayBufferSize];
    int _crossDelayIndex;
    
    // Spatial Widener DSP state
    float _widenerDelayBuffer[kWidenerDelayBufferSize];
    int _widenerDelayIndex;
    float _widenerHighpassL;
    float _widenerHighpassR;
}

+ (instancetype) sharedProcessor {
    static SPAudioProcessor *sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[SPAudioProcessor alloc] init];
    });
    return sInstance;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger savedCrossfeed = [defaults objectForKey:kPrefKeyCrossfeedMode] ? [defaults integerForKey:kPrefKeyCrossfeedMode] : SPCrossfeedModeNatural;
        NSInteger savedWidener = [defaults objectForKey:kPrefKeyWidenerMode] ? [defaults integerForKey:kPrefKeyWidenerMode] : SPSpatialWidenerOff;
        
        _crossfeedMode.store((int)savedCrossfeed);
        _spatialWidenerMode.store((int)savedWidener);
        
        [self resetFilterState];
    }
    return self;
}

- (void) resetFilterState {
    _leftLowpass = 0.0f;
    _rightLowpass = 0.0f;
    memset(_crossDelayL, 0, sizeof(_crossDelayL));
    memset(_crossDelayR, 0, sizeof(_crossDelayR));
    _crossDelayIndex = 0;
    
    memset(_widenerDelayBuffer, 0, sizeof(_widenerDelayBuffer));
    _widenerDelayIndex = 0;
    _widenerHighpassL = 0.0f;
    _widenerHighpassR = 0.0f;
}

#pragma mark - Properties & Toggles

- (SPCrossfeedMode) crossfeedMode {
    return (SPCrossfeedMode)_crossfeedMode.load();
}

- (void) setCrossfeedMode:(SPCrossfeedMode)mode {
    _crossfeedMode.store((int)mode);
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kPrefKeyCrossfeedMode];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPAudioProcessorCrossfeedChangedNotification object:self];
    });
}

- (SPSpatialWidenerMode) spatialWidenerMode {
    return (SPSpatialWidenerMode)_spatialWidenerMode.load();
}

- (void) setSpatialWidenerMode:(SPSpatialWidenerMode)mode {
    _spatialWidenerMode.store((int)mode);
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kPrefKeyWidenerMode];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SPAudioProcessorWidenerChangedNotification object:self];
    });
}

- (void) cycleCrossfeedMode {
    SPCrossfeedMode current = self.crossfeedMode;
    SPCrossfeedMode next;
    switch (current) {
        case SPCrossfeedModeNatural: next = SPCrossfeedModeSubtle; break;
        case SPCrossfeedModeSubtle:  next = SPCrossfeedModeOff; break;
        case SPCrossfeedModeOff:     next = SPCrossfeedModeMono; break;
        case SPCrossfeedModeMono:    next = SPCrossfeedModeNatural; break;
        default:                     next = SPCrossfeedModeNatural; break;
    }
    self.crossfeedMode = next;
}

- (void) cycleSpatialWidenerMode {
    SPSpatialWidenerMode current = self.spatialWidenerMode;
    SPSpatialWidenerMode next;
    switch (current) {
        case SPSpatialWidenerOff:    next = SPSpatialWidenerSubtle; break;
        case SPSpatialWidenerSubtle: next = SPSpatialWidenerWide; break;
        case SPSpatialWidenerWide:   next = SPSpatialWidenerOff; break;
        default:                     next = SPSpatialWidenerOff; break;
    }
    self.spatialWidenerMode = next;
}

- (NSString *) localizedCrossfeedName {
    switch (self.crossfeedMode) {
        case SPCrossfeedModeNatural: return @"Natural Crossfeed (Headphones)";
        case SPCrossfeedModeSubtle:  return @"Subtle Crossfeed";
        case SPCrossfeedModeOff:     return @"Off (Authentic Hard Stereo)";
        case SPCrossfeedModeMono:    return @"Mono Downmix";
    }
}

- (NSString *) localizedSpatialWidenerName {
    switch (self.spatialWidenerMode) {
        case SPSpatialWidenerOff:    return @"Off (Authentic Mono)";
        case SPSpatialWidenerSubtle: return @"Subtle Room Ambiance";
        case SPSpatialWidenerWide:   return @"Expansive Soundstage";
    }
}

#pragma mark - Real-Time Audio DSP Processing

- (void) processStereoBuffer:(short *)buffer
                  frameCount:(int)frameCount
                  sampleRate:(int)sampleRate
                       isMod:(BOOL)isMod
                    sidChips:(int)sidChips
{
    if (buffer == nullptr || frameCount <= 0) {
        return;
    }
    
    int rate = (sampleRate > 8000) ? sampleRate : 44100;
    SPCrossfeedMode cfMode = (SPCrossfeedMode)_crossfeedMode.load();
    SPSpatialWidenerMode widenerMode = (SPSpatialWidenerMode)_spatialWidenerMode.load();
    
    // Check if tune is single-SID mono tune
    BOOL isMonoSid = (!isMod && sidChips <= 1);
    
    // ------------------------------------------------------------------------
    // Step 1: Optional Spatial Widener for Single-SID (Mono) Tunes
    // ------------------------------------------------------------------------
    if (isMonoSid && widenerMode != SPSpatialWidenerOff) {
        // Haas delay: ~12.5ms for Subtle (~550 samples at 44.1kHz), ~17ms for Wide (~750 samples)
        int haasDelaySamples = (widenerMode == SPSpatialWidenerWide) ? (int)(rate * 0.017f) : (int)(rate * 0.0125f);
        if (haasDelaySamples >= kWidenerDelayBufferSize) {
            haasDelaySamples = kWidenerDelayBufferSize - 1;
        }
        
        float directGain = (widenerMode == SPSpatialWidenerWide) ? 0.75f : 0.85f;
        float delayedGain = (widenerMode == SPSpatialWidenerWide) ? 0.45f : 0.32f;
        float decorrGain  = (widenerMode == SPSpatialWidenerWide) ? 0.18f : 0.12f;
        
        // Highpass filter for phase decorrelation (~1.2 kHz)
        float hpCutoff = 1200.0f;
        float hpOmega = 2.0f * (float)M_PI * hpCutoff / (float)rate;
        float hpAlpha = 1.0f / (1.0f + hpOmega);
        
        for (int i = 0; i < frameCount; i++) {
            float inSample = (float)buffer[i * 2]; // Both L and R are identical mono
            
            // Store into delay line
            _widenerDelayBuffer[_widenerDelayIndex] = inSample;
            int readIdx = _widenerDelayIndex - haasDelaySamples;
            if (readIdx < 0) {
                readIdx += kWidenerDelayBufferSize;
            }
            float delayed = _widenerDelayBuffer[readIdx];
            _widenerDelayIndex = (_widenerDelayIndex + 1) % kWidenerDelayBufferSize;
            
            // Highpass calculation: hp = alpha * (hp_prev + in - in_prev)
            _widenerHighpassL = hpAlpha * (_widenerHighpassL + inSample);
            float decorr = inSample - _widenerHighpassL;
            
            float outL = inSample * directGain + decorr * decorrGain;
            float outR = inSample * (directGain * 0.85f) + delayed * delayedGain - decorr * decorrGain;
            
            buffer[i * 2]     = softClip(outL);
            buffer[i * 2 + 1] = softClip(outR);
        }
    }
    
    // ------------------------------------------------------------------------
    // Step 2: Headphone Crossfeed Filter (Meier/Bauer Model)
    // ------------------------------------------------------------------------
    if (cfMode == SPCrossfeedModeOff) {
        // Bypass crossfeed (100% hard stereo)
        return;
    }
    
    if (cfMode == SPCrossfeedModeMono) {
        // Pure mono downmix
        for (int i = 0; i < frameCount; i++) {
            short l = buffer[i * 2];
            short r = buffer[i * 2 + 1];
            short mono = (short)(((int)l + (int)r) / 2);
            buffer[i * 2]     = mono;
            buffer[i * 2 + 1] = mono;
        }
        return;
    }
    
    // Active Headphone Crossfeed Filter
    // Cutoff ~700 Hz (natural diffraction around adult human head)
    float fc = 700.0f;
    float omega = 2.0f * (float)M_PI * fc / (float)rate;
    float alpha = omega / (omega + 1.0f);
    
    int delaySamples;
    float gDirect;
    float gCross;
    
    if (cfMode == SPCrossfeedModeNatural) {
        // Meier model: ~300µs ITD delay (~13 samples at 44.1kHz), -8dB crossfeed
        delaySamples = (int)(rate * 0.00030f);
        gDirect = 0.72f;
        gCross  = 0.28f;
    } else { // SPCrossfeedModeSubtle
        // Subtle model: ~160µs delay, -16dB crossfeed
        delaySamples = (int)(rate * 0.00016f);
        gDirect = 0.86f;
        gCross  = 0.14f;
    }
    
    if (delaySamples >= kCrossfeedDelayBufferSize) {
        delaySamples = kCrossfeedDelayBufferSize - 1;
    }
    if (delaySamples < 1) {
        delaySamples = 1;
    }
    
    for (int i = 0; i < frameCount; i++) {
        float inL = (float)buffer[i * 2];
        float inR = (float)buffer[i * 2 + 1];
        
        // Single-pole low-pass filter for contralateral ear
        _leftLowpass  += alpha * (inL - _leftLowpass);
        _rightLowpass += alpha * (inR - _rightLowpass);
        
        // Write low-passed signals to circular ITD delay lines
        _crossDelayL[_crossDelayIndex] = _leftLowpass;
        _crossDelayR[_crossDelayIndex] = _rightLowpass;
        
        int rIdx = _crossDelayIndex - delaySamples;
        if (rIdx < 0) {
            rIdx += kCrossfeedDelayBufferSize;
        }
        
        float delayedLowL = _crossDelayL[rIdx];
        float delayedLowR = _crossDelayR[rIdx];
        
        _crossDelayIndex = (_crossDelayIndex + 1) % kCrossfeedDelayBufferSize;
        
        // Crossfeed summing: Left ear gets direct Left + delayed low-pass Right
        float outL = inL * gDirect + delayedLowR * gCross;
        float outR = inR * gDirect + delayedLowL * gCross;
        
        buffer[i * 2]     = softClip(outL);
        buffer[i * 2 + 1] = softClip(outR);
    }
}

@end
