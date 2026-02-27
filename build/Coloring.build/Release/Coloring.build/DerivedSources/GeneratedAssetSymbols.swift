import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "InkBlack" asset catalog color resource.
    static let inkBlack = DeveloperToolsSupport.ColorResource(name: "InkBlack", bundle: resourceBundle)

    /// The "SprayBlue" asset catalog color resource.
    static let sprayBlue = DeveloperToolsSupport.ColorResource(name: "SprayBlue", bundle: resourceBundle)

    /// The "SprayGreen" asset catalog color resource.
    static let sprayGreen = DeveloperToolsSupport.ColorResource(name: "SprayGreen", bundle: resourceBundle)

    /// The "SprayOrange" asset catalog color resource.
    static let sprayOrange = DeveloperToolsSupport.ColorResource(name: "SprayOrange", bundle: resourceBundle)

    /// The "SprayRed" asset catalog color resource.
    static let sprayRed = DeveloperToolsSupport.ColorResource(name: "SprayRed", bundle: resourceBundle)

    /// The "SprayViolet" asset catalog color resource.
    static let sprayViolet = DeveloperToolsSupport.ColorResource(name: "SprayViolet", bundle: resourceBundle)

    /// The "SprayYellow" asset catalog color resource.
    static let sprayYellow = DeveloperToolsSupport.ColorResource(name: "SprayYellow", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

}

