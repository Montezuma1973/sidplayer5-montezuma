//
//  SPKnurledKnobControl.h
//  SIDPLAY
//
//  Non-standard tactile rotary knob control with knurled aluminum dial,
//  LED indicator arc collar, and radial mouse dragging physics.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKnobColor) {
    SPKnobColorCyan = 0,
    SPKnobColorAmber,
    SPKnobColorEmerald,
    SPKnobColorPurple
};

@interface SPKnurledKnobControl : NSControl

@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@property (nonatomic, assign) float knobValue;
@property (nonatomic, assign) SPKnobColor ledColor;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *unitText;
@property (nonatomic, assign) BOOL showArcMeter;

- (instancetype)initWithFrame:(NSRect)frameRect
                        title:(NSString *)title
                         unit:(NSString *)unit
                     minValue:(float)minVal
                     maxValue:(float)maxVal
                 initialValue:(float)initVal
                        color:(SPKnobColor)color;

@end

NS_ASSUME_NONNULL_END
