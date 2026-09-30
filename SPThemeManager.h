#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SPAppTheme) {
    SPAppThemeSystem = 0,         // Modern macOS System (Default dynamic light/dark)
    SPAppThemeC64 = 1,            // Commodore 64 Classic
    SPAppThemeWorkbench13 = 2,    // Amiga Workbench 1.3
    SPAppThemeWorkbench31 = 3     // Amiga Workbench 3.1
};

extern NSString * const SPThemeDidChangeNotification;
extern NSString * const kSPAppThemePrefKey;

@interface SPThemeManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) SPAppTheme currentTheme;

- (void)applyTheme:(SPAppTheme)theme;
- (void)cycleTheme;
- (NSString *)themeNameForTheme:(SPAppTheme)theme;
- (NSString *)currentThemeName;

// Theme Colors
- (NSColor *)windowBackgroundColor;
- (NSColor *)browserBackgroundColor;
- (NSColor *)browserAlternatingRowColor;
- (NSColor *)browserGridColor;
- (NSColor *)browserTextColor;
- (NSColor *)browserSecondaryTextColor;
- (NSColor *)browserSelectionColor;
- (NSColor *)browserSelectionTextColor;

- (NSColor *)sourceListBackgroundColor;
- (NSColor *)sourceListTextColor;
- (NSColor *)sourceListHeaderColor;
- (NSColor *)sourceListSelectionColor;
- (NSColor *)sourceListSelectionTextColor;

- (NSColor *)boxGradientStartColor;
- (NSColor *)boxGradientEndColor;
- (NSColor *)boxBorderColor;

- (NSColor *)visualizerBackgroundColor;
- (NSColor *)accentColor;
- (NSAppearance *)windowAppearance;

@end
