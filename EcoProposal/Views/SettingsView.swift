import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudSession.self) private var cloud: CloudSession?

    @AppStorage(CompanyInfo.Keys.taxRate) private var taxRate: Double = 0
    @AppStorage(CompanyInfo.Keys.terms)   private var terms: String   = CompanyInfo.fallbackTerms

    private let company = CompanyInfo.load()

    /// Marketing version + build number from the bundle, e.g. "1.2 (7)".
    static var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build != version {
            return "\(version) (\(build))"
        }
        return version
    }

    var body: some View {
        Form {
            Section("Company") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.name)
                        .font(.headline)
                    Text(company.street)
                    Text(company.cityStateZip)
                    Text(company.phone)
                    Text(company.website)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            Section("EcoProposal Cloud") {
                if let profile = cloud?.profile {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(profile.fullName, systemImage: "person.crop.circle.fill")
                            .font(.headline)
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Role", value: profile.roleDisplayName)
                    LabeledContent("Last synced") {
                        if let synced = CloudSyncState.shared.lastSyncedAt {
                            Text(synced, format: .relative(presentation: .named))
                        } else {
                            Text("Not yet")
                        }
                    }
                    if let syncError = CloudSync.shared.lastError {
                        Text("Sync problem: \(syncError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await CloudSync.shared.pullNow() }
                    } label: {
                        if CloudSync.shared.isSyncing {
                            HStack { ProgressView(); Text("Syncing…") }
                        } else {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(CloudSync.shared.isSyncing)
                    Button(role: .destructive) {
                        Task { await cloud?.signOut() }
                    } label: {
                        Label("Sign out of EcoProposal Cloud", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Proposal defaults") {
                HStack {
                    Text("Default tax rate")
                    Spacer()
                    TextField(
                        "Tax rate",
                        value: Binding(
                            get: { taxRate * 100 },
                            set: { taxRate = $0 / 100 }
                        ),
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .iosKeyboardType(.decimal)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("%")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default terms & conditions")
                        .font(.subheadline)
                    TextField("Terms", text: $terms, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            Section {
                NavigationLink("Document library") {
                    DocumentLibraryView()
                }
            } header: {
                Text("Literature")
            } footer: {
                Text("Manage brochures and spec sheets that can be attached to any proposal.")
            }
            Section {
                NavigationLink("OneDrive") {
                    OneDriveSettingsView()
                }
                NavigationLink("Quickbase (coming soon)") {
                    QuickbasePlaceholderView()
                }
            } header: {
                Text("Integrations")
            }
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.appVersionDisplay)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .iosInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct OneDriveSettingsView: View {
    @State private var client: LiveOneDriveClient?
    @State private var signInError: String?
    @State private var isSigningIn = false

    var body: some View {
        Form {
            Section {
                if let client, let account = client.account {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(account.displayName, systemImage: "person.crop.circle.fill")
                            .font(.headline)
                        Text(account.userPrincipalName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        Task { try? await client.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSigningIn {
                            HStack { ProgressView(); Text("Signing in…") }
                        } else {
                            Label("Sign in with Microsoft 365", systemImage: "cloud")
                        }
                    }
                    .disabled(isSigningIn || client == nil)
                }
                if let signInError {
                    Text(signInError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Sign in with your Eco Seal Microsoft 365 account. Proposals will save to the /EcoProposal folder in your OneDrive.")
            }
        }
        .navigationTitle("OneDrive")
        .iosInlineNavigationTitle()
        .task {
            if client == nil {
                client = LiveOneDriveClient()
            }
        }
    }

    private func signIn() async {
        guard let client else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            try await client.signIn()
        } catch {
            signInError = error.localizedDescription
        }
    }
}

private struct QuickbasePlaceholderView: View {
    var body: some View {
        List {
            Section {
                Label("Not yet connected", systemImage: "cloud.slash")
                Text("Quickbase sync will be enabled once realm, table, and token details are configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Quickbase")
    }
}
