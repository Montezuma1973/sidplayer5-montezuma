#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SPRetroVisualizerMode) {
    SPRetroVisualizerModeAuto = 0,       // Auto: Amiga Boing Ball for MOD, Datasette Tape for SID
    SPRetroVisualizerModeBoingBall = 1,   // Amiga Boing Ball (1984 demo)
    SPRetroVisualizerModeCassette = 2,    // Commodore Datasette C-60 Tape
    SPRetroVisualizerModeFloppy = 3,      // Commodore 1541 5.25" Floppy Drive
    SPRetroVisualizerModeSpectrum = 4     // Classic Equalizer Spectrum Bars
};

@interface SPSpectrumView : NSView

@property (nonatomic, assign) SPRetroVisualizerMode visualizerMode;

- (void)updateWithSamples:(const short *)samples count:(int)count sampleRate:(int)sampleRate;

- (void)updatePlaybackState:(BOOL)isPlaying
                      isMod:(BOOL)isMod
                   playTime:(NSTimeInterval)playTime
                  totalTime:(NSTimeInterval)totalTime
                  tuneTitle:(NSString *)tuneTitle;

- (void)cycleVisualizerMode;

@end
