import SwiftUI

/// Eco-Seal Home Solutions logo lockup. Uses the actual brand image asset shipped in
/// `Assets.xcassets/EcoSealLogo`. Scales to fit whatever frame it's given while
/// preserving the horizontal aspect ratio.
struct BrandLogo: View {
    /// Target height in points. Width is inferred from the image aspect ratio.
    var height: CGFloat = 36

    var body: some View {
        Image("EcoSealLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Eco-Seal Home Solutions")
    }
}

#Preview {
    BrandLogo(height: 60)
        .padding()
}
