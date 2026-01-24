#import <Cocoa/Cocoa.h>

@interface SPSpectrumView : NSView

- (void)updateWithSamples:(const short *)samples count:(int)count sampleRate:(int)sampleRate;

@end
