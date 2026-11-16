import Foundation

/// Marker protocol for SwiftData models that can be synced to Quickbase.
/// Each conformer knows its Quickbase table id and how to build a record payload.
protocol QuickbaseSyncable: AnyObject {
    var remoteRecordID: Int? { get set }
    var updatedAt: Date { get set }
}

extension Customer: QuickbaseSyncable {}
extension Job: QuickbaseSyncable {}
extension Proposal: QuickbaseSyncable {}
extension LineItem: QuickbaseSyncable {}
extension JobPhoto: QuickbaseSyncable {}

/// Phase 1 scaffold. Phase 2 will implement against https://api.quickbase.com/v1
/// using headers:
///   QB-Realm-Hostname: <realm>
///   Authorization: QB-USER-TOKEN <token>
///   Content-Type: application/json
/// - `upsert`  -> POST /records
/// - `pull`    -> POST /records/query
actor QuickbaseClient {
    private let config: QuickbaseConfig
    private let session: URLSession

    init(config: QuickbaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Push a single record to Quickbase. Not implemented in Phase 1.
    func upsert(_ model: any QuickbaseSyncable) async throws {
        // TODO: Phase 2 — build the record payload from the model's field map,
        // POST to /records, then read back the assigned RID and store it on the model.
        throw QuickbaseClientError.notImplemented
    }

    /// Pull changes newer than the given date. Not implemented in Phase 1.
    func pullChanges(since date: Date) async throws -> [String: [[String: Any]]] {
        // TODO: Phase 2 — for each table, POST /records/query with a
        // where clause on "updated" > date, decode into rows keyed by table id.
        throw QuickbaseClientError.notImplemented
    }
}

enum QuickbaseClientError: LocalizedError {
    case notImplemented
    case notConfigured
    case badResponse(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Quickbase sync is not yet enabled in this build."
        case .notConfigured:
            return "Quickbase connection is not configured. Add realm, token, and table IDs in Settings."
        case .badResponse(let status, let body):
            return "Quickbase returned HTTP \(status). \(body ?? "")"
        }
    }
}
