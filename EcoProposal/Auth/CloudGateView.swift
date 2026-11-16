import SwiftUI

/// Second gate, inside the Microsoft 365 gate: connects the rep to EcoProposal
/// Cloud (Supabase) so proposals can sync with the web app. Uses the same
/// Microsoft account, so it is usually a single tap.
struct CloudGateView<Content: View>: View {
    @State private var cloud = CloudSession()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            switch cloud.state {
            case .checking:
                ZStack {
                    Color.ecoNavy.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            case .signedOut:
                CloudConnectView(cloud: cloud)
            case .notProvisioned:
                CloudNotProvisionedView(cloud: cloud)
            case .ready:
                content()
                    // Two-way sync with EcoPRO Cloud while signed in.
                    .task { CloudSync.shared.startAutoSync(context: modelContext, profile: cloud.profile) }
            }
        }
        .environment(cloud)
        .task { await cloud.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, cloud.state == .ready {
                Task { await CloudSync.shared.syncNow() }
            }
        }
    }
}

private struct CloudConnectView: View {
    @Bindable var cloud: CloudSession

    var body: some View {
        ZStack {
            Color.ecoNavy.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ecoGreen)
                VStack(spacing: 8) {
                    Text("Connect to EcoPRO Cloud")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Proposals, customers and the literature library sync between this iPad and the EcoPRO website. Use your Eco Seal Microsoft account.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Button {
                    Task { await cloud.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if cloud.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "person.badge.key.fill")
                        }
                        Text(cloud.isWorking ? "Connecting…" : "Continue with Microsoft")
                            .font(.headline)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 15)
                    .background(Color.ecoGreen, in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(cloud.isWorking)

                if let message = cloud.errorMessage {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Spacer()
            }
            .padding()
        }
    }
}

private struct CloudNotProvisionedView: View {
    @Bindable var cloud: CloudSession

    var body: some View {
        ZStack {
            Color.ecoNavy.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                Text("Your account isn't set up yet")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("You're signed in, but you don't have an active EcoPRO profile. Ask an administrator to set up your account.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack(spacing: 16) {
                    Button("Try again") {
                        Task { await cloud.refreshProfile(showErrors: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ecoGreen)
                    Button("Sign out") {
                        Task { await cloud.signOut() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .padding()
        }
    }
}
