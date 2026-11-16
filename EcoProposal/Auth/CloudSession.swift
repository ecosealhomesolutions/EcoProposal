import Foundation
import Observation
import AuthenticationServices
import Supabase

/// The signed-in user's row from the `profiles` table.
struct CloudProfile: Codable, Equatable {
    let id: UUID
    let orgId: UUID
    let fullName: String
    let email: String
    let role: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case fullName = "full_name"
        case email
        case role
        case active
    }

    var roleDisplayName: String {
        switch role {
        case "admin":      return "Admin"
        case "manager":    return "Manager"
        case "sales_rep":  return "Sales Rep"
        case "technician": return "Technician"
        case "office":     return "Office"
        default:           return role.capitalized
        }
    }
}

/// Supabase sign-in state for the iPad app (Phase 3, session 1).
///
/// Offline-first: once a rep has signed in, the saved session and a cached copy
/// of their profile let the app open on job sites with no signal. The profile is
/// refreshed in the background whenever the network is available.
@MainActor
@Observable
final class CloudSession {
    enum State: Equatable {
        case checking        // launch: looking for a saved session
        case signedOut       // needs "Continue with Microsoft"
        case notProvisioned  // signed in, but no active EcoPRO profile
        case ready           // signed in with an active profile
    }

    private(set) var state: State = .checking
    private(set) var profile: CloudProfile?
    private(set) var isWorking = false
    var errorMessage: String?

    private let client = SupabaseService.client
    private static let cachedProfileKey = "cloud.profile"

    // MARK: - Launch

    func start() async {
        guard client.auth.currentSession != nil else {
            state = .signedOut
            return
        }
        if let cached = Self.loadCachedProfile() {
            // Let the rep straight in, then refresh quietly.
            apply(cached)
            await refreshProfile(showErrors: false)
        } else {
            await refreshProfile(showErrors: true)
        }
    }

    // MARK: - Sign in / out

    func signIn() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await client.auth.signInWithOAuth(
                provider: .azure,
                redirectTo: SupabaseService.authRedirectURL,
                scopes: "email"
            )
        } catch {
            if let webError = error as? ASWebAuthenticationSessionError, webError.code == .canceledLogin {
                return  // rep closed the sign-in sheet
            }
            errorMessage = "Couldn't connect to EcoPRO Cloud. \(error.localizedDescription)"
            return
        }
        await refreshProfile(showErrors: true)
    }

    func signOut() async {
        CloudSync.shared.stopAutoSync()
        try? await client.auth.signOut()
        UserDefaults.standard.removeObject(forKey: Self.cachedProfileKey)
        profile = nil
        errorMessage = nil
        state = .signedOut
    }

    // MARK: - Profile

    /// Loads the rep's row from `profiles`. Row-level security only returns the
    /// rep's own organization, so this also confirms they belong to Eco-Seal.
    func refreshProfile(showErrors: Bool) async {
        do {
            let session = try await client.auth.session
            let rows: [CloudProfile] = try await client
                .from("profiles")
                .select("id, org_id, full_name, email, role, active")
                .eq("id", value: session.user.id.uuidString)
                .limit(1)
                .execute()
                .value

            if let row = rows.first {
                Self.saveCachedProfile(row)
                apply(row)
            } else {
                profile = nil
                state = .notProvisioned
            }
            errorMessage = nil
        } catch {
            if client.auth.currentSession == nil {
                // Session is gone (revoked, expired and not refreshable).
                profile = nil
                state = .signedOut
                if showErrors { errorMessage = "Please sign in again." }
            } else if profile == nil {
                // Signed in but couldn't reach the server and nothing cached yet.
                state = .signedOut
                if showErrors {
                    errorMessage = "Couldn't reach EcoPRO Cloud. Check your connection and try again."
                }
            }
            // Otherwise: offline with a cached profile, keep working.
        }
    }

    private func apply(_ row: CloudProfile) {
        profile = row
        state = row.active ? .ready : .notProvisioned
    }

    // MARK: - Offline cache

    private static func loadCachedProfile() -> CloudProfile? {
        guard let data = UserDefaults.standard.data(forKey: cachedProfileKey) else { return nil }
        return try? JSONDecoder().decode(CloudProfile.self, from: data)
    }

    private static func saveCachedProfile(_ profile: CloudProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: cachedProfileKey)
        }
    }
}
