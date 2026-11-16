import Foundation

/// OneDrive / Microsoft 365 connection settings.
///
/// The Client ID and Tenant ID are baked into the app binary — they are not secrets
/// in the public-client OAuth flow (Microsoft's own iOS apps ship with theirs the
/// same way). What guarantees only this app can receive tokens is the redirect URI
/// binding to the bundle identifier + the interactive user sign-in. Reps never see
/// or configure these values.
struct OneDriveConfig: Equatable {
    /// Application (client) ID GUID from Entra ID → App registrations → Overview.
    let clientID: String = "d55834c2-ac29-41a5-8f3f-d790d093dc6c"
    /// Directory (tenant) ID GUID — single-tenant Eco Seal Solutions.
    let tenantID: String = "62613112-06d4-43c2-8be9-5eefa4b63e77"
    /// Folder in the signed-in user's OneDrive where proposals will land.
    let folderPath: String = "EcoProposal"

    /// Redirect URI the Entra ID app registration is configured with.
    /// Format is fixed by MSAL for iOS: `msauth.<bundle-id>://auth`.
    var redirectURI: String { "msauth.\(Bundle.main.bundleIdentifier ?? "")://auth" }

    /// Graph API scopes the app requests on sign-in.
    var scopes: [String] { ["Files.ReadWrite", "User.Read"] }

    /// Authority URL bounded to the Eco Seal tenant only.
    var authorityURL: String {
        "https://login.microsoftonline.com/\(tenantID)"
    }

    var isConfigured: Bool {
        !clientID.isEmpty && !tenantID.isEmpty
    }
}

/// The identity of a signed-in Microsoft 365 user.
struct OneDriveAccount: Codable, Equatable {
    var displayName: String
    var userPrincipalName: String       // e.g. "jane@ecosealsolutions.com"
    var accountID: String               // MSAL homeAccountId

    static let storageKey = "onedrive.account"

    static func load(from defaults: UserDefaults = .standard) -> OneDriveAccount? {
        guard let data = defaults.data(forKey: storageKey),
              let account = try? JSONDecoder().decode(OneDriveAccount.self, from: data)
        else { return nil }
        return account
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
