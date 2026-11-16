import SwiftUI

/// Full-screen branded login shown before the app opens. Sign-in goes through
/// Microsoft 365 (MSAL) and only @ecosealsolutions.com accounts are allowed past.
struct LoginView: View {
    @Bindable var auth: AuthManager

    var body: some View {
        ZStack {
            Color.ecoNavy.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                BrandLogo(height: 72)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                    )

                VStack(spacing: 8) {
                    Text("EcoPRO")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Sign in with your Eco Seal Solutions account to continue.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if auth.isWorking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.key.fill")
                        }
                        Text(auth.isWorking ? "Signing in…" : "Sign in with Microsoft 365")
                            .font(.headline)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 15)
                    .background(Color.ecoGreen, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(auth.isWorking)

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .padding(.horizontal)
                }

                Spacer()

                Text("Access is limited to @\(AuthManager.allowedDomain) users.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 12)
            }
            .padding()
        }
    }
}

#Preview {
    LoginView(auth: AuthManager())
}
