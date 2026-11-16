import SwiftUI

#if os(iOS)
import UIKit
#endif

extension View {
    /// Applies `.keyboardType(_:)` on iOS/Catalyst, no-op on macOS.
    @ViewBuilder
    func iosKeyboardType(_ type: KeyboardTypeShim) -> some View {
        #if os(iOS)
        self.keyboardType(type.uiType)
        #else
        self
        #endif
    }

    /// Applies `.textInputAutocapitalization(.never)` on iOS, no-op on macOS.
    @ViewBuilder
    func iosNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Applies `.textInputAutocapitalization(.characters)` on iOS, no-op on macOS.
    @ViewBuilder
    func iosUppercaseAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }

    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS, no-op on macOS.
    @ViewBuilder
    func iosInlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

enum KeyboardTypeShim {
    case decimal, phone, email, url, numberPad

    #if os(iOS)
    var uiType: UIKeyboardType {
        switch self {
        case .decimal:   return .decimalPad
        case .phone:     return .phonePad
        case .email:     return .emailAddress
        case .url:       return .URL
        case .numberPad: return .numberPad
        }
    }
    #endif
}

extension ToolbarItemPlacement {
    /// Leading placement that works on both platforms.
    static var leadingCompat: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }
}
