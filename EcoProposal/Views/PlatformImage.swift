import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-platform helpers for turning raw image `Data` into a SwiftUI `Image`.
enum PlatformImage {
    static func image(from data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #elseif os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    /// Native image (for use with PKDrawing rasterization or aspect calculations).
    #if os(iOS)
    static func uiImage(from data: Data) -> UIImage? { UIImage(data: data) }
    #elseif os(macOS)
    static func nsImage(from data: Data) -> NSImage? { NSImage(data: data) }
    #endif
}
