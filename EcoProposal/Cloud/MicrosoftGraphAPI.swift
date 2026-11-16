import Foundation

/// Minimal Microsoft Graph client — accepts a bearer token and hits the endpoints
/// EcoProposal needs (drive upload, current-user profile). Independent of MSAL so it
/// can be exercised in isolation once we have an access token.
struct MicrosoftGraphAPI {
    var baseURL: URL = URL(string: "https://graph.microsoft.com/v1.0")!
    var session: URLSession = .shared

    /// Uploads a small file (< 4 MB) to `/me/drive/root:/<folder>/<filename>:/content`.
    /// For larger files switch to a resumable upload session — deferred until we hit that ceiling.
    func uploadFile(
        accessToken: String,
        folderPath: String,
        filename: String,
        data: Data,
        contentType: String = "application/pdf"
    ) async throws -> DriveItem {
        let encodedPath = "\(folderPath)/\(filename)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "\(folderPath)/\(filename)"
        let url = baseURL.appendingPathComponent("me/drive/root:/\(encodedPath):/content")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (body, response) = try await session.data(for: request)
        try Self.throwIfBadResponse(response, body: body)
        return try JSONDecoder().decode(DriveItem.self, from: body)
    }

    /// Fetches the signed-in user's profile — used to display "Signed in as <name>" in Settings.
    func currentUser(accessToken: String) async throws -> GraphUser {
        var request = URLRequest(url: baseURL.appendingPathComponent("me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (body, response) = try await session.data(for: request)
        try Self.throwIfBadResponse(response, body: body)
        return try JSONDecoder().decode(GraphUser.self, from: body)
    }

    private static func throwIfBadResponse(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MicrosoftGraphError.badResponse(status: -1, body: nil)
        }
        guard 200..<300 ~= http.statusCode else {
            throw MicrosoftGraphError.badResponse(status: http.statusCode, body: String(data: body, encoding: .utf8))
        }
    }
}

// MARK: - DTOs

struct DriveItem: Codable, Equatable {
    var id: String
    var name: String
    var webUrl: URL?
    var size: Int?
}

struct GraphUser: Codable, Equatable {
    var displayName: String?
    var userPrincipalName: String?
    var id: String
}

enum MicrosoftGraphError: LocalizedError {
    case badResponse(status: Int, body: String?)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You need to sign in to OneDrive first."
        case .badResponse(let status, let body):
            return "OneDrive returned HTTP \(status). \(body ?? "")"
        }
    }
}
