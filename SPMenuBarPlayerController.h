#import <Cocoa/Cocoa.h>

@class SPPlayerWindow;

NS_ASSUME_NONNULL_BEGIN

@interface SPMenuBarPlayerController : NSObject

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, weak) SPPlayerWindow *playerWindow;

+ (instancetype)sharedController;

- (void)setupWithPlayerWindow:(SPPlayerWindow *)window;
- (void)updatePlaybackState:(BOOL)isPlaying;
- (void)updatePlaybackTime:(NSTimeInterval)currentTime totalTime:(NSTimeInterval)totalTime isPlaying:(BOOL)isPlaying;
- (void)updateTuneTitle:(NSString *)title
                 author:(NSString *)author
            releaseInfo:(NSString *)releaseInfo
                subtune:(NSInteger)subtune
           subtuneCount:(NSInteger)subtuneCount
                 length:(NSInteger)length
                   chip:(NSString *)chip
                  isMod:(BOOL)isMod;
- (void)updateLoopMode;
- (void)updateVolume;
- (void)updateViewMenuCheck;

- (IBAction)toggleMenuBarItem:(id)sender;

@end

NS_ASSUME_NONNULL_END
