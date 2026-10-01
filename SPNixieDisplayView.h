//
//  SPNixieDisplayView.h
//  SIDPLAY
//
//  Warm glowing neon Nixie tube display view with cylindrical glass
//  envelopes, internal wire anode grids, and filament glow.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPNixieDisplayView : NSView

@property (nonatomic, assign) NSInteger seconds;
@property (nonatomic, assign) int subtune;
@property (nonatomic, assign) int subtuneCount;
@property (nonatomic, assign) BOOL showSubtune; // If YES, displays "01/05", if NO displays "MM:SS"

- (void)setTimeInSeconds:(NSInteger)sec;
- (void)setSubtune:(int)subtune count:(int)count;

@end

NS_ASSUME_NONNULL_END
