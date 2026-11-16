import Foundation
import Observation

/// Remembers which local records are linked to EcoProposal Cloud and what was
/// last exchanged with it, so the iPad can tell its own unsent edits apart from
/// changes made on the website.
///
/// Kept in its own small JSON file (Application Support) instead of new
/// SwiftData fields, so the existing on-device database is never migrated or
/// reset by the sync work. Every key is optional when reading, so older copies
/// of this file always load.
@MainActor
@Observable
final class CloudSyncState {
    static let shared = CloudSyncState()

    struct Stored: Codable {
        var proposalIDs: Set<UUID> = []
        var customerIDs: Set<UUID> = []
        var jobIDs: Set<UUID> = []
        var lineItemIDs: Set<UUID> = []
        var libraryIDs: Set<UUID> = []
        var salesRepNames: [String] = []
        var lastSyncedAt: Date?

        // Session 3: two-way sync bookkeeping
        var proposalVersions: [UUID: Int] = [:]
        var proposalOwners: [UUID: UUID] = [:]
        var proposalCollaborators: [UUID: [UUID]] = [:]
        var lockedProposalIDs: Set<UUID> = []
        var proposalLineItemIDs: [UUID: [UUID]] = [:]
        var proposalFingerprints: [UUID: String] = [:]
        var notesFingerprints: [UUID: String] = [:]
        var scopeHTMLHashes: [UUID: String] = [:]
        var customerFingerprints: [UUID: String] = [:]
        var jobFingerprints: [UUID: String] = [:]

        // Session 4: files
        var uploadedPhotoImages: Set<UUID> = []
        var photoFingerprints: [UUID: String] = [:]
        var proposalPhotoIDs: [UUID: [UUID]] = [:]
        var sketchFingerprints: [UUID: String] = [:]
        var uploadedSignatures: Set<String> = []
        var uploadedDocuments: Set<UUID> = []
        var documentFingerprints: [UUID: String] = [:]
        var proposalDocumentIDs: [UUID: [UUID]] = [:]

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            proposalIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .proposalIDs) ?? []
            customerIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .customerIDs) ?? []
            jobIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .jobIDs) ?? []
            lineItemIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .lineItemIDs) ?? []
            libraryIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .libraryIDs) ?? []
            salesRepNames = try c.decodeIfPresent([String].self, forKey: .salesRepNames) ?? []
            lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
            proposalVersions = try c.decodeIfPresent([UUID: Int].self, forKey: .proposalVersions) ?? [:]
            proposalOwners = try c.decodeIfPresent([UUID: UUID].self, forKey: .proposalOwners) ?? [:]
            proposalCollaborators = try c.decodeIfPresent([UUID: [UUID]].self, forKey: .proposalCollaborators) ?? [:]
            lockedProposalIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .lockedProposalIDs) ?? []
            proposalLineItemIDs = try c.decodeIfPresent([UUID: [UUID]].self, forKey: .proposalLineItemIDs) ?? [:]
            proposalFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .proposalFingerprints) ?? [:]
            notesFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .notesFingerprints) ?? [:]
            scopeHTMLHashes = try c.decodeIfPresent([UUID: String].self, forKey: .scopeHTMLHashes) ?? [:]
            customerFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .customerFingerprints) ?? [:]
            jobFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .jobFingerprints) ?? [:]
            uploadedPhotoImages = try c.decodeIfPresent(Set<UUID>.self, forKey: .uploadedPhotoImages) ?? []
            photoFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .photoFingerprints) ?? [:]
            proposalPhotoIDs = try c.decodeIfPresent([UUID: [UUID]].self, forKey: .proposalPhotoIDs) ?? [:]
            sketchFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .sketchFingerprints) ?? [:]
            uploadedSignatures = try c.decodeIfPresent(Set<String>.self, forKey: .uploadedSignatures) ?? []
            uploadedDocuments = try c.decodeIfPresent(Set<UUID>.self, forKey: .uploadedDocuments) ?? []
            documentFingerprints = try c.decodeIfPresent([UUID: String].self, forKey: .documentFingerprints) ?? [:]
            proposalDocumentIDs = try c.decodeIfPresent([UUID: [UUID]].self, forKey: .proposalDocumentIDs) ?? [:]
        }
    }

    /// Everything above. Mutated only by `CloudSync`; call `save()` afterwards.
    var stored = Stored()

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

    func save() {
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
