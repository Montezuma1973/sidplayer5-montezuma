#import "SPThemeManager.h"

NSString * const SPThemeDidChangeNotification = @"SPThemeDidChangeNotification";
NSString * const kSPAppThemePrefKey = @"SPAppTheme";

@implementation SPThemeManager

+ (instancetype)sharedManager
{
    static SPThemeManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:kSPAppThemePrefKey] != nil) {
            _currentTheme = (SPAppTheme)[defaults integerForKey:kSPAppThemePrefKey];
        } else {
            _currentTheme = SPAppThemeSystem;
        }
    }
    return self;
}

- (void)setCurrentTheme:(SPAppTheme)theme
{
    if (_currentTheme != theme) {
        _currentTheme = theme;
        [[NSUserDefaults standardUserDefaults] setInteger:theme forKey:kSPAppThemePrefKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPThemeDidChangeNotification object:self];
    }
}

- (void)applyTheme:(SPAppTheme)theme
{
    self.currentTheme = theme;
}

- (void)cycleTheme
{
    SPAppTheme nextTheme = (self.currentTheme + 1) % 4;
    [self applyTheme:nextTheme];
}

- (NSString *)themeNameForTheme:(SPAppTheme)theme
{
    switch (theme) {
        case SPAppThemeC64:
            return @"Commodore 64 Classic";
        case SPAppThemeWorkbench13:
            return @"Amiga Workbench 1.3";
        case SPAppThemeWorkbench31:
            return @"Amiga Workbench 3.1";
        case SPAppThemeSystem:
        default:
            return @"System Default (macOS)";
    }
}

- (NSString *)currentThemeName
{
    return [self themeNameForTheme:self.currentTheme];
}

#pragma mark - Window & Appearance

- (NSColor *)windowBackgroundColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            // C64 VIC-II Border Purple-Blue
            return [NSColor colorWithCalibratedRed:0.251f green:0.192f blue:0.553f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Amiga OCS Deep Blue
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeWorkbench31:
            // Amiga AGA Neutral Grey
            return [NSColor colorWithCalibratedRed:0.667f green:0.667f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor windowBackgroundColor];
    }
}

- (NSAppearance *)windowAppearance
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
        case SPAppThemeWorkbench13:
            return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        case SPAppThemeWorkbench31:
            return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        case SPAppThemeSystem:
        default:
            return nil; // Follows system dynamic mode
    }
}

#pragma mark - Browser View Colors

- (NSColor *)browserBackgroundColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            // C64 Screen Blue
            return [NSColor colorWithCalibratedRed:0.208f green:0.157f blue:0.475f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Amiga Workbench Blue
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeWorkbench31:
            // Amiga Workbench 3.1 Grey
            return [NSColor colorWithCalibratedRed:0.667f green:0.667f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor controlBackgroundColor];
    }
}

- (NSColor *)browserAlternatingRowColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            // Slightly deeper C64 stripe
            return [NSColor colorWithCalibratedRed:0.173f green:0.129f blue:0.404f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Slightly deeper Amiga blue stripe
            return [NSColor colorWithCalibratedRed:0.000f green:0.282f blue:0.565f alpha:1.0f];
        case SPAppThemeWorkbench31:
            // Slightly lighter AGA grey stripe
            return [NSColor colorWithCalibratedRed:0.710f green:0.710f blue:0.710f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return nil;
    }
}

- (NSColor *)browserGridColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.290f green:0.227f blue:0.620f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.000f green:0.200f blue:0.450f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.550f green:0.550f blue:0.550f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor gridColor];
    }
}

- (NSColor *)browserTextColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            // C64 Light Blue / Lavender Text
            return [NSColor colorWithCalibratedRed:0.647f green:0.647f blue:1.000f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Amiga Crisp White Text
            return [NSColor colorWithCalibratedRed:1.000f green:1.000f blue:1.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            // Amiga Deep Charcoal Text
            return [NSColor colorWithCalibratedRed:0.000f green:0.000f blue:0.000f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor labelColor];
    }
}

- (NSColor *)browserSecondaryTextColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.533f green:0.494f blue:0.796f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.667f green:0.800f blue:1.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.231f green:0.231f blue:0.231f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor secondaryLabelColor];
    }
}

- (NSColor *)browserSelectionColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.369f green:0.302f blue:0.659f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Amiga Topaz Orange Highlight Bar
            return [NSColor colorWithCalibratedRed:1.000f green:0.533f blue:0.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            // Workbench 3.1 Blue Selection Bar
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor selectedContentBackgroundColor];
    }
}

- (NSColor *)browserSelectionTextColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor whiteColor];
        case SPAppThemeWorkbench13:
            // Amiga Inverted Black Text on Orange Bar
            return [NSColor blackColor];
        case SPAppThemeWorkbench31:
            return [NSColor whiteColor];
        case SPAppThemeSystem:
        default:
            return [NSColor selectedControlTextColor];
    }
}

#pragma mark - Source List Colors

- (NSColor *)sourceListBackgroundColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.188f green:0.141f blue:0.439f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.000f green:0.267f blue:0.533f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.745f green:0.745f blue:0.745f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor clearColor];
    }
}

- (NSColor *)sourceListTextColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.647f green:0.647f blue:1.000f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:1.000f green:1.000f blue:1.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.000f green:0.000f blue:0.000f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor labelColor];
    }
}

- (NSColor *)sourceListHeaderColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            // C64 VIC-II Yellow header
            return [NSColor colorWithCalibratedRed:0.933f green:0.933f blue:0.467f alpha:1.0f];
        case SPAppThemeWorkbench13:
            // Topaz Orange header
            return [NSColor colorWithCalibratedRed:1.000f green:0.533f blue:0.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor secondaryLabelColor];
    }
}

- (NSColor *)sourceListSelectionColor
{
    return [self browserSelectionColor];
}

- (NSColor *)sourceListSelectionTextColor
{
    return [self browserSelectionTextColor];
}

#pragma mark - Box & Gradient View Colors

- (NSColor *)boxGradientStartColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.251f green:0.192f blue:0.553f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.784f green:0.784f blue:0.784f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return nil;
    }
}

- (NSColor *)boxGradientEndColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.208f green:0.157f blue:0.475f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.000f green:0.267f blue:0.533f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.667f green:0.667f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return nil;
    }
}

- (NSColor *)boxBorderColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.533f green:0.494f blue:0.796f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:1.000f green:0.533f blue:0.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.333f green:0.333f blue:0.333f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return nil;
    }
}

#pragma mark - Visualizer & Accents

- (NSColor *)visualizerBackgroundColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.208f green:0.157f blue:0.475f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.667f green:0.667f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor colorWithCalibratedWhite:0.0f alpha:0.15f];
    }
}

- (NSColor *)accentColor
{
    switch (self.currentTheme) {
        case SPAppThemeC64:
            return [NSColor colorWithCalibratedRed:0.533f green:0.494f blue:0.796f alpha:1.0f];
        case SPAppThemeWorkbench13:
            return [NSColor colorWithCalibratedRed:1.000f green:0.533f blue:0.000f alpha:1.0f];
        case SPAppThemeWorkbench31:
            return [NSColor colorWithCalibratedRed:0.000f green:0.333f blue:0.667f alpha:1.0f];
        case SPAppThemeSystem:
        default:
            return [NSColor controlAccentColor];
    }
}

@end
