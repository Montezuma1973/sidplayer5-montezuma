#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SPRetroVisualizerMode) {
    SPRetroVisualizerModeAuto = 0,       // Auto: Amiga Boing Ball for MOD, Datasette Tape for SID
    SPRetroVisualizerModeBoingBall = 1,   // Amiga Boing Ball (1984 demo)
    SPRetroVisualizerModeCassette = 2,    // Commodore Datasette C-60 Tape
    SPRetroVisualizerModeFloppy = 3,      // Commodore 1541 5.25" Floppy Drive
    SPRetroVisualizerModeSpectrum = 4,    // Classic Equalizer Spectrum Bars
    SPRetroVisualizerModeTracker = 5,     // Live Tracker Pattern Matrix
    SPRetroVisualizerModePianoRoll = 6    // Retro Piano Roll Waterfall
};

typedef NS_ENUM(NSInteger, SPCRTDisplayProfile) {
    SPCRTDisplayProfile1084SColor = 0,    // Commodore 1084S Color RGB CRT
    SPCRTDisplayProfileAmber = 1,         // Vintage Monochrome Amber Phosphor
    SPCRTDisplayProfileGreen = 2,         // Classic Monochrome Green Phosphor
    SPCRTDisplayProfileC64Cyan = 3        // C64 Blue / Cyan Phosphor
};

@interface SPSpectrumView : NSView

@property (nonatomic, assign) SPRetroVisualizerMode visualizerMode;
@property (nonatomic, assign) BOOL crtEffectEnabled;
@property (nonatomic, assign) SPCRTDisplayProfile crtProfile;
@property (nonatomic, copy) NSString *chipModel;
@property (nonatomic, weak) id ownerWindow;

- (void)updateWithSamples:(const short *)samples count:(int)count sampleRate:(int)sampleRate;

- (void)updatePlaybackState:(BOOL)isPlaying
                      isMod:(BOOL)isMod
                   playTime:(NSTimeInterval)playTime
                  totalTime:(NSTimeInterval)totalTime
                  tuneTitle:(NSString *)tuneTitle;

- (void)updatePlaybackState:(BOOL)isPlaying
                      isMod:(BOOL)isMod
                   playTime:(NSTimeInterval)playTime
                  totalTime:(NSTimeInterval)totalTime
                  tuneTitle:(NSString *)tuneTitle
                  chipModel:(NSString *)chipModel;

- (void)cycleVisualizerMode;
- (void)toggleCRTEffect;
- (void)cycleCRTProfile;

@end
