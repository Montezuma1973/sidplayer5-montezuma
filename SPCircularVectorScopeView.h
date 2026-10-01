//
//  SPCircularVectorScopeView.h
//  SIDPLAY
//
//  Circular Radar Phosphor Vector Oscilloscope with Lissajous,
//  Circular Waveform, and Radar Sweep modes.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SPVectorScopeMode) {
    SPVectorScopeModeLissajousXY = 0,    // Stereo X/Y phase scope
    SPVectorScopeModeCircularWave = 1,   // 360-degree radial audio wave
    SPVectorScopeModeRadarSweep = 2      // Rotating beam radar sweep
};

@class SPPlayerWindow;

@interface SPCircularVectorScopeView : NSView

@property (nonatomic, assign) SPVectorScopeMode scopeMode;
@property (nonatomic, strong) NSColor *phosphorColor;
@property (nonatomic, weak) SPPlayerWindow *playerWindow;
@property (nonatomic, assign) BOOL isRunning;

- (void)startScope;
- (void)stopScope;
- (void)cycleScopeMode;

@end
