#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"dn.coloring";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "InkBlack" asset catalog color resource.
static NSString * const ACColorNameInkBlack AC_SWIFT_PRIVATE = @"InkBlack";

/// The "SprayBlue" asset catalog color resource.
static NSString * const ACColorNameSprayBlue AC_SWIFT_PRIVATE = @"SprayBlue";

/// The "SprayGreen" asset catalog color resource.
static NSString * const ACColorNameSprayGreen AC_SWIFT_PRIVATE = @"SprayGreen";

/// The "SprayOrange" asset catalog color resource.
static NSString * const ACColorNameSprayOrange AC_SWIFT_PRIVATE = @"SprayOrange";

/// The "SprayRed" asset catalog color resource.
static NSString * const ACColorNameSprayRed AC_SWIFT_PRIVATE = @"SprayRed";

/// The "SprayViolet" asset catalog color resource.
static NSString * const ACColorNameSprayViolet AC_SWIFT_PRIVATE = @"SprayViolet";

/// The "SprayYellow" asset catalog color resource.
static NSString * const ACColorNameSprayYellow AC_SWIFT_PRIVATE = @"SprayYellow";

#undef AC_SWIFT_PRIVATE
