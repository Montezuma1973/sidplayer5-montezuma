//
//  SPNowPlayingArtworkGenerator.h
//  SIDPLAY
//
//  Created for Milestone 5.2: System Media Keys & macOS Now Playing Integration.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPNowPlayingArtworkGenerator : NSObject

/// Generates procedural retro album cover artwork (Amiga Boing Ball / Commodore Datasette Cassette)
+ (NSImage *)artworkForTitle:(NSString *)title
                      artist:(NSString *)artist
                       isMod:(BOOL)isMod
                   chipModel:(NSString *)chipModel
                     subtune:(int)subtune
                subtuneCount:(int)subtuneCount
                        size:(CGSize)size;

@end

NS_ASSUME_NONNULL_END
