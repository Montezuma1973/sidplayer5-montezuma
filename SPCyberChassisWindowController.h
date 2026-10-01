//
//  SPCyberChassisWindowController.h
//  SIDPLAY
//
//  Window Controller for the Cyber-Chassis Deck
//

#import <Cocoa/Cocoa.h>

@class SPPlayerWindow;
@class SPCyberChassisDeckView;

@interface SPCyberChassisWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, weak) SPPlayerWindow *playerWindow;
@property (nonatomic, strong, readonly) SPCyberChassisDeckView *deckView;
@property (nonatomic, readonly) BOOL isDeckWindowVisible;

+ (instancetype)sharedController;

- (void)setupWithPlayerWindow:(SPPlayerWindow *)playerWindow;
- (IBAction)showDeckWindow:(id)sender;
- (IBAction)toggleDeckWindow:(id)sender;

@end
