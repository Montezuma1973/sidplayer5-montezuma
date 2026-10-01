#import <Cocoa/Cocoa.h>

@class SPPlayerWindow;
@class SPSpectrumView;

NS_ASSUME_NONNULL_BEGIN

@interface SPFloatingWidgetWindow : NSPanel
@end

@interface SPVisualizerPlaceholderView : NSView
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@interface SPFloatingWidgetController : NSObject

@property (nonatomic, readonly) BOOL isDetached;
@property (nonatomic, assign) BOOL alwaysOnTop;
@property (nonatomic, weak, nullable) SPPlayerWindow *playerWindow;
@property (nonatomic, weak, nullable) SPSpectrumView *spectrumView;

+ (instancetype)sharedController;

- (void)setupWithPlayerWindow:(SPPlayerWindow *)playerWindow spectrumView:(SPSpectrumView *)spectrumView;
- (void)detachVisualizer;
- (void)dockVisualizer;
- (void)toggleFloatingWidget;
- (void)updateOverlayInfoWithTitle:(NSString *)title author:(NSString *)author chip:(NSString *)chip isMod:(BOOL)isMod;
- (void)updateViewMenuChecks;

@end

NS_ASSUME_NONNULL_END
