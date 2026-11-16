import SwiftUI
import MSAL

/// Gates the whole app behind a Microsoft 365 sign-in. Only accounts on the
/// company domain (`@ecosealsolutions.com`) get past the login screen — everyone
/// else is signed straight back out. Two layers enforce this:
///   1. The MSAL authority is already pinned to the Eco Seal tenant
///      (`OneDriveConfig.authorityURL`), so foreign Microsoft accounts can't get
///      a token at all.
///   2. `AuthManager` rejects any tenant account (e.g. an invited guest) whose
///      email isn't on the company domain.
struct AuthGateView<Content: View>: View {
    @State private var auth = AuthManager()
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if auth.isSignedIn {
                content()
            } else {
                LoginView(auth: auth)
            }
        }
        .task { await auth.start() }
    }
}

/// Login state for the app. Wraps the same MSAL client the OneDrive upload flow
/// uses, so signing in here also signs the rep into OneDrive.
@MainActor
@Observable
final class AuthManager {
    /// Emails must end with this to use the app.
    static let allowedDomain = "ecosealsolutions.com"

    private let client = LiveOneDriveClient()

    private(set) var isSignedIn = false
    private(set) var isWorking = false
    var errorMessage: String?

    var accountName: String? { client.account?.displayName }

    /// Launch check. A cached company account gets in immediately — reps often
    /// open the app on job sites with no signal, so we don't block on the network.
    /// A silent token check then runs in the background and only forces re-login
    /// if Microsoft explicitly says the session is no longer valid (revoked,
    /// password reset, account disabled).
    func start() async {
        guard let account = client.account else { return }
        guard Self.isAllowed(account.userPrincipalName) else {
            // A pre-gate install signed in with a non-company account — clear it.
            try? await client.signOut()
            return
        }
        isSignedIn = true

        if await client.validateSession() == .needsInteraction {
            try? await client.signOut()
            isSignedIn = false
            errorMessage = "Your Microsoft 365 session has expired. Please sign in again."
        }
    }

    func signIn() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await client.signIn()
        } catch {
            // Rep closing the sign-in sheet isn't an error worth showing.
            let nsError = error as NSError
            if nsError.domain == MSALErrorDomain,
               nsError.code == MSALError.userCanceled.rawValue {
                return
            }
            errorMessage = Self.friendlyMessage(for: nsError)
            return
        }

        guard let account = client.account else {
            errorMessage = "Sign-in didn't return an account. Please try again."
            return
        }
        guard Self.isAllowed(account.userPrincipalName) else {
            try? await client.signOut()
            errorMessage = "Access is limited to @\(Self.allowedDomain) accounts. Sign in with your Eco Seal Solutions email."
            return
        }
        isSignedIn = true
    }

    static func isAllowed(_ userPrincipalName: String) -> Bool {
        userPrincipalName.lowercased().hasSuffix("@" + allowedDomain)
    }

    /// MSAL wraps its real failure inside userInfo — the bare localizedDescription
    /// is often just "(MSALErrorDomain error -50000)", which is undiagnosable.
    /// Surface the internal description/code so the rep can report something useful.
    static func friendlyMessage(for error: NSError) -> String {
        guard error.domain == MSALErrorDomain else { return error.localizedDescription }

        var parts: [String] = []
        if let description = error.userInfo[MSALErrorDescriptionKey] as? String, !description.isEmpty {
            parts.append(description)
        }
        if let internalCode = error.userInfo[MSALInternalErrorCodeKey] as? Int {
            parts.append("(internal code \(internalCode))")
        }
        if parts.isEmpty {
            return error.localizedDescription
        }
        return "Sign-in failed: " + parts.joined(separator: " ")
    }
}
