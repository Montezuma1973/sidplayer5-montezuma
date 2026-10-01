//
//  SPAudioProcessor.h
//  SIDPLAY
//
//  Created for Milestone 5: Audio Engine Architecture, Headphone Crossfeed & Spatial Widener.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPCrossfeedMode) {
    SPCrossfeedModeNatural = 0,     // Natural Headphone Crossfeed (Meier/Bauer low-pass ITD filter, optimal for headphones)
    SPCrossfeedModeSubtle  = 1,     // Subtle Crossfeed (preserves expansive soundstage with reduced ear fatigue)
    SPCrossfeedModeOff     = 2,     // Off / Authentic Hardware (100% hard stereo pan for Paula & dual-SID)
    SPCrossfeedModeMono    = 3      // Mono Downmix (both ears receive (L + R) / 2)
};

typedef NS_ENUM(NSInteger, SPSpatialWidenerMode) {
    SPSpatialWidenerOff    = 0,     // Off (Authentic centered mono for single-SID)
    SPSpatialWidenerSubtle = 1,     // Subtle Room Ambiance (Haas psychoacoustic widening + decorrelation)
    SPSpatialWidenerWide   = 2      // Expansive Retro Soundstage
};

extern NSString * const SPAudioProcessorCrossfeedChangedNotification;
extern NSString * const SPAudioProcessorWidenerChangedNotification;

@interface SPAudioProcessor : NSObject

@property (nonatomic, assign) SPCrossfeedMode crossfeedMode;
@property (nonatomic, assign) SPSpatialWidenerMode spatialWidenerMode;

+ (instancetype) sharedProcessor;

- (void) cycleCrossfeedMode;
- (void) cycleSpatialWidenerMode;

- (NSString *) localizedCrossfeedName;
- (NSString *) localizedSpatialWidenerName;

/// Process 16-bit interleaved stereo PCM buffer in-place
- (void) processStereoBuffer:(short *)buffer
                  frameCount:(int)frameCount
                  sampleRate:(int)sampleRate
                       isMod:(BOOL)isMod
                    sidChips:(int)sidChips;

- (void) resetFilterState;

@end

NS_ASSUME_NONNULL_END
