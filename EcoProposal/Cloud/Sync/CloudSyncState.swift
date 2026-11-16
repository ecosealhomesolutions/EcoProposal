import Foundation
import Observation

/// Remembers which local records came from EcoProposal Cloud, plus the
/// downloaded rep list and the last sync time.
///
/// Kept in its own small JSON file (Application Support) instead of new
/// SwiftData fields, so the existing on-device database is never migrated or
/// reset by the sync work.
@MainActor
@Observable
final class CloudSyncState {
    static let shared = CloudSyncState()

    private struct Stored: Codable {
        var proposalIDs: Set<UUID> = []
        var customerIDs: Set<UUID> = []
        var jobIDs: Set<UUID> = []
        var lineItemIDs: Set<UUID> = []
        var libraryIDs: Set<UUID> = []
        var salesRepNames: [String] = []
        var lastSyncedAt: Date?
    }

    private var stored = Stored()

    var proposalIDs: Set<UUID> { stored.proposalIDs }
    var customerIDs: Set<UUID> { stored.customerIDs }
    var jobIDs: Set<UUID> { stored.jobIDs }
    var lineItemIDs: Set<UUID> { stored.lineItemIDs }
    var libraryIDs: Set<UUID> { stored.libraryIDs }
    var salesRepNames: [String] { stored.salesRepNames }
    var lastSyncedAt: Date? { stored.lastSyncedAt }
    var hasCloudLibrary: Bool { !stored.libraryIDs.isEmpty }

    func isCloudProposal(_ id: UUID) -> Bool { stored.proposalIDs.contains(id) }

    /// Sales rep names for pickers: everyone with an EcoProposal Cloud profile, merged
    /// with the built-in list so reps who haven't signed in yet still appear.
    /// (Session 5 retires the built-in list once every rep has an account.)
    func salesRepNames(fallback: [String]) -> [String] {
        var seen = Set<String>()
        return (stored.salesRepNames + fallback)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted()
    }

    func update(
        proposals: Set<UUID>? = nil,
        customers: Set<UUID>? = nil,
        jobs: Set<UUID>? = nil,
        lineItems: Set<UUID>? = nil,
        library: Set<UUID>? = nil,
        salesReps: [String]? = nil,
        syncedAt: Date? = nil
    ) {
        if let proposals { stored.proposalIDs = proposals }
        if let customers { stored.customerIDs = customers }
        if let jobs { stored.jobIDs = jobs }
        if let lineItems { stored.lineItemIDs = lineItems }
        if let library { stored.libraryIDs = library }
        if let salesReps { stored.salesRepNames = salesReps }
        if let syncedAt { stored.lastSyncedAt = syncedAt }
        save()
    }

    // MARK: - File

    private init() { load() }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CloudSyncState.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        stored = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
