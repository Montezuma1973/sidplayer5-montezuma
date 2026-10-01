//
//  SPCyberChassisDeckView.h
//  SIDPLAY
//
//  Brushed Gunmetal Cyber-Chassis Deck View
//  Integrating Nixie Tube Display, Circular Phosphor Vector Scope,
//  Knurled Aluminum Rotary Knobs, and Chrome Bat Toggle Switches.
//

#import <Cocoa/Cocoa.h>
#import "SPNixieDisplayView.h"
#import "SPCircularVectorScopeView.h"
#import "SPKnurledKnobControl.h"
#import "SPToggleSwitchControl.h"

@class SPPlayerWindow;

@interface SPCyberChassisDeckView : NSView

@property (nonatomic, weak) SPPlayerWindow *playerWindow;

// Subviews
@property (nonatomic, strong, readonly) SPNixieDisplayView *timeNixieView;
@property (nonatomic, strong, readonly) SPNixieDisplayView *subtuneNixieView;
@property (nonatomic, strong, readonly) NSButton *prevSubtuneBtn;
@property (nonatomic, strong, readonly) NSButton *nextSubtuneBtn;
@property (nonatomic, strong, readonly) SPCircularVectorScopeView *vectorScopeView;

@property (nonatomic, strong, readonly) SPKnurledKnobControl *volumeKnob;
@property (nonatomic, strong, readonly) SPKnurledKnobControl *tempoKnob;
@property (nonatomic, strong, readonly) SPKnurledKnobControl *filterKnob;

@property (nonatomic, strong, readonly) SPToggleSwitchControl *playPauseToggle;
@property (nonatomic, strong, readonly) SPToggleSwitchControl *loopToggle;
@property (nonatomic, strong, readonly) SPToggleSwitchControl *stereoSidToggle;
@property (nonatomic, strong, readonly) SPToggleSwitchControl *scopeModeToggle;

- (void)updatePlayerState;

@end
