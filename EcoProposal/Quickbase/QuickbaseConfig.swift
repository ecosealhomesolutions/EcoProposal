import Foundation

/// Quickbase connection + table/field mapping.
/// Phase 1: stored in `UserDefaults`. Phase 2 TODO: move `userToken` into the Keychain.
struct QuickbaseConfig: Codable, Equatable {
    var realmHostname: String = ""      // e.g. "ecoseal.quickbase.com"
    var appId: String = ""              // Quickbase app dbid
    var userToken: String = ""          // "b6yh...": user token from Quickbase

    // Table dbids
    var customerTableId: String = ""
    var jobTableId: String = ""
    var proposalTableId: String = ""
    var lineItemTableId: String = ""

    // Field-ID mappings per table.
    // Values are the numeric field IDs (fid) from Quickbase.
    // Populate before enabling Phase 2 sync.
    var customerFields: [String: Int] = [:]
    var jobFields: [String: Int] = [:]
    var proposalFields: [String: Int] = [:]
    var lineItemFields: [String: Int] = [:]

    /// Whether the config has the minimum required fields to attempt a sync.
    var isReadyForSync: Bool {
        !realmHostname.isEmpty && !userToken.isEmpty &&
        !proposalTableId.isEmpty && !customerTableId.isEmpty
    }

    static let storageKey = "quickbase.config"

    static func load(from defaults: UserDefaults = .standard) -> QuickbaseConfig {
        guard let data = defaults.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(QuickbaseConfig.self, from: data)
        else {
            return QuickbaseConfig()
        }
        return config
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
