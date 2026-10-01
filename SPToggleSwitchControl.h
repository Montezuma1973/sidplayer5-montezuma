//
//  SPToggleSwitchControl.h
//  SIDPLAY
//
//  Non-standard tactile chrome bat toggle switch control with mechanical
//  spring action, mounting nut, and status LED.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPToggleLedColor) {
    SPToggleLedColorCyan = 0,
    SPToggleLedColorAmber,
    SPToggleLedColorEmerald,
    SPToggleLedColorRed
};

@interface SPToggleSwitchControl : NSControl

@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, assign) SPToggleLedColor ledColor;

- (instancetype)initWithFrame:(NSRect)frameRect
                        title:(NSString *)title
                         isOn:(BOOL)isOn
                     ledColor:(SPToggleLedColor)color;

@end

NS_ASSUME_NONNULL_END
