import Foundation
import MSAL
#if canImport(UIKit)
import UIKit
#endif

/// Errors surfaced to the UI by the OneDrive integration.
enum OneDriveClientError: LocalizedError {
    case notConfigured
    case notSignedIn
    case noPresentingViewController
    case msalInitFailed(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OneDrive isn't set up yet. Go to Settings → OneDrive to add the Microsoft app registration."
        case .notSignedIn:
            return "Sign in to OneDrive first from Settings."
        case .noPresentingViewController:
            return "Couldn't find a view controller to present the sign-in sheet from."
        case .msalInitFailed(let message):
            return "Couldn't initialize the Microsoft sign-in library: \(message)"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Abstraction over the OneDrive integration.
protocol OneDriveClient: AnyObject {
    var config: OneDriveConfig { get }
    var account: OneDriveAccount? { get }

    func signIn() async throws
    func signOut() async throws

    /// Uploads a file to `folder/filename` in the signed-in user's OneDrive and
    /// returns the web URL of the resulting item. Pass `nil` for `folder` to use
    /// the app default (`config.folderPath`).
    func uploadPDF(fileURL: URL, filename: String, folder: String?) async throws -> URL
}

@MainActor
@Observable
final class LiveOneDriveClient: OneDriveClient {
    let config = OneDriveConfig()
    private(set) var account: OneDriveAccount?

    private let graph = MicrosoftGraphAPI()
    private var msalApp: MSALPublicClientApplication?
    private var lastMSALInitError: Error?

    init() {
        self.account = OneDriveAccount.load()
        rebuildMSALApp()
    }

    private func rebuildMSALApp() {
        guard let authorityURL = URL(string: config.authorityURL) else {
            msalApp = nil
            lastMSALInitError = nil
            return
        }
        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let msalConfig = MSALPublicClientApplicationConfig(
                clientId: config.clientID,
                redirectUri: config.redirectURI,
                authority: authority
            )
            msalApp = try MSALPublicClientApplication(configuration: msalConfig)
            lastMSALInitError = nil
        } catch {
            print("MSAL init failed: \(error) — redirectURI was \(config.redirectURI)")
            msalApp = nil
            lastMSALInitError = error
        }
    }

    // MARK: - Sign-in / sign-out

    func signIn() async throws {
        guard config.isConfigured else { throw OneDriveClientError.notConfigured }
        guard let msalApp else {
            let detail = lastMSALInitError.map { "\($0)" }
                ?? "no underlying error"
            throw OneDriveClientError.msalInitFailed(
                "\(detail). Redirect URI expected: \(config.redirectURI)"
            )
        }

        #if os(iOS)
        guard let presentingVC = Self.rootViewController() else {
            throw OneDriveClientError.noPresentingViewController
        }
        let webParams = MSALWebviewParameters(authPresentationViewController: presentingVC)
        #else
        let webParams = MSALWebviewParameters()
        #endif

        let interactive = MSALInteractiveTokenParameters(
            scopes: config.scopes,
            webviewParameters: webParams
        )
        interactive.promptType = .selectAccount

        let result: MSALResult = try await withCheckedThrowingContinuation { cont in
            msalApp.acquireToken(with: interactive) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let result {
                    cont.resume(returning: result)
                } else {
                    cont.resume(throwing: OneDriveClientError.msalInitFailed("empty result"))
                }
            }
        }

        // Pull the friendlier display name from Graph. Falls back to UPN if the profile call fails.
        let profile = try? await graph.currentUser(accessToken: result.accessToken)
        let username = result.account.username ?? ""

        let acc = OneDriveAccount(
            displayName: profile?.displayName ?? username,
            userPrincipalName: username,
            accountID: result.account.identifier ?? ""
        )
        acc.save()
        self.account = acc
    }

    /// Outcome of a silent session check, used by the login gate at launch.
    enum SessionStatus {
        case valid              // token refreshed silently — session is good
        case needsInteraction   // Microsoft requires a fresh sign-in (revoked/expired)
        case unknown            // network or transient failure — don't lock the rep out
    }

    /// Silently re-validates the cached account's session. Distinguishes "Microsoft
    /// revoked this session" from "we're offline in a basement" so field reps without
    /// signal aren't kicked back to the login screen.
    func validateSession() async -> SessionStatus {
        guard let account, let msalApp,
              let msalAccount = try? msalApp.account(forIdentifier: account.accountID)
        else { return .needsInteraction }

        let silent = MSALSilentTokenParameters(scopes: config.scopes, account: msalAccount)
        return await withCheckedContinuation { cont in
            msalApp.acquireTokenSilent(with: silent) { result, error in
                if result != nil {
                    cont.resume(returning: .valid)
                } else if let nsError = error as NSError?,
                          nsError.domain == MSALErrorDomain,
                          nsError.code == MSALError.interactionRequired.rawValue {
                    cont.resume(returning: .needsInteraction)
                } else {
                    cont.resume(returning: .unknown)
                }
            }
        }
    }

    func signOut() async throws {
        // Try to remove the account from the MSAL cache so the next sign-in starts clean.
        if let msalApp,
           let identifier = account?.accountID,
           let cached = try? msalApp.account(forIdentifier: identifier) {
            try? msalApp.remove(cached)
        }
        account = nil
        OneDriveAccount.clear()
    }

    // MARK: - Upload

    func uploadPDF(fileURL: URL, filename: String, folder: String?) async throws -> URL {
        guard config.isConfigured else { throw OneDriveClientError.notConfigured }
        guard let account, let msalApp else { throw OneDriveClientError.notSignedIn }

        let msalAccount: MSALAccount
        do {
            msalAccount = try msalApp.account(forIdentifier: account.accountID)
        } catch {
            throw OneDriveClientError.notSignedIn
        }

        let silent = MSALSilentTokenParameters(scopes: config.scopes, account: msalAccount)

        let result: MSALResult = try await withCheckedThrowingContinuation { cont in
            msalApp.acquireTokenSilent(with: silent) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let result {
                    cont.resume(returning: result)
                } else {
                    cont.resume(throwing: OneDriveClientError.notSignedIn)
                }
            }
        }

        let data = try Data(contentsOf: fileURL)
        let resolvedFolder = Self.sanitizeFolder(folder) ?? config.folderPath
        let resolvedFilename = Self.sanitizeFilename(filename)
        let item = try await graph.uploadFile(
            accessToken: result.accessToken,
            folderPath: resolvedFolder,
            filename: resolvedFilename,
            data: data
        )
        return item.webUrl ?? fileURL
    }

    /// Trims whitespace and strips leading/trailing slashes; returns nil if empty.
    private static func sanitizeFolder(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Ensures the filename ends in `.pdf` and strips characters OneDrive won't accept.
    private static func sanitizeFilename(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: #"\/:*?"<>|"#)
        var trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: illegal)
            .joined(separator: "-")
        if trimmed.isEmpty { trimmed = "Proposal.pdf" }
        if !trimmed.lowercased().hasSuffix(".pdf") { trimmed += ".pdf" }
        return trimmed
    }

    // MARK: - Helpers

    #if os(iOS)
    private static func rootViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}
