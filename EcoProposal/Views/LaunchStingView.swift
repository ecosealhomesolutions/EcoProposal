import SwiftUI

/// 1.6-second EcoPRO logo sting shown once when the app launches:
/// the shield rises in from the bottom (like water filling it), "EcoPRO" lifts in,
/// the green underline draws, then everything fades into the app.
/// Tap to skip. With Reduce Motion on, it's a short still frame instead.
/// The background matches the launch screen color (LaunchNavy) so there's no flash.
struct LaunchStingView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shieldIn = false
    @State private var wordIn = false
    @State private var lineIn = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.ecoNavy.ignoresSafeArea()

            VStack(spacing: 22) {
                Image("EcoProShield")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128)
                    // Reveal from the bottom up
                    .mask(alignment: .bottom) {
                        Rectangle().scaleEffect(x: 1, y: shieldIn ? 1 : 0, anchor: .bottom)
                    }
                    .scaleEffect(shieldIn ? 1 : 0.85)
                    .opacity(shieldIn ? 1 : 0)

                VStack(spacing: 10) {
                    Text("EcoPRO")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(wordIn ? 1 : 0)
                        .offset(y: wordIn ? 0 : 12)

                    Capsule()
                        .fill(Color.ecoGreen)
                        .frame(width: lineIn ? 64 : 0, height: 4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EcoPRO")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            shieldIn = true; wordIn = true; lineIn = true
            try? await Task.sleep(for: .milliseconds(600))
            finish()
            return
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)) { shieldIn = true }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeOut(duration: 0.4)) { wordIn = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.3)) { lineIn = true }
        try? await Task.sleep(for: .milliseconds(650))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

#Preview {
    LaunchStingView { }
}
