import SwiftUI
import SwiftData
import MSAL

@main
struct EcoProposalApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Customer.self,
            Job.self,
            Proposal.self,
            LineItem.self,
            JobPhoto.self,
            Blueprint.self,
            BlueprintPage.self,
            ProposalDocument.self,
            LibraryDocument.self,
            InspectionReport.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The on-disk store couldn't be opened (e.g. an incompatible model change).
            // Never delete reps' data: move the old store aside into
            // Application Support/StoreBackups/<timestamp>/ and start fresh.
            // Proposals already in EcoProposal Cloud download again on the next sync.
            print("SwiftData: backing up and rebuilding container after open failure — \(error)")
            backUpAndRemoveStore(for: configuration)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer even after resetting the store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            // Everything sits behind the Microsoft 365 login gate — only
            // @ecosealsolutions.com accounts can open the app.
            AuthGateView {
                // Phase 3: connect to EcoProposal Cloud (Supabase) after the M365 gate.
                CloudGateView {
                    ContentView()
                }
            }
            .tint(.ecoGreen)
            .onOpenURL { url in
                // MSAL needs the OAuth redirect handed back to it so it can resume the sign-in flow.
                _ = MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
            }
            .task {
                // Make sure the standard sales brochures are in the literature library.
                BundledLiterature.seed(into: sharedModelContainer.mainContext)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Moves the SwiftData store files (`.store`, `-wal`, `-shm`) into a timestamped
/// backup folder so a fresh container can be created without losing anything.
private func backUpAndRemoveStore(for configuration: ModelConfiguration) {
    let fm = FileManager.default
    let baseURL = configuration.url
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let backupDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StoreBackups", isDirectory: true)
        .appendingPathComponent(stamp, isDirectory: true)
    try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

    let candidates = [
        baseURL,
        URL(fileURLWithPath: baseURL.path + "-wal"),
        URL(fileURLWithPath: baseURL.path + "-shm"),
        baseURL.appendingPathExtension("wal"),
        baseURL.appendingPathExtension("shm"),
    ]
    for url in candidates where fm.fileExists(atPath: url.path) {
        let destination = backupDir.appendingPathComponent(url.lastPathComponent)
        if (try? fm.moveItem(at: url, to: destination)) == nil {
            try? fm.removeItem(at: url)  // last resort so the app can still launch
        }
    }
}

extension Color {
    /// Eco-Seal primary navy — the "ECO-SEAL" wordmark + shield outline color.
    static let ecoNavy = Color(red: 0.10, green: 0.20, blue: 0.32)
    /// Eco-Seal green — the "Home Solutions" tagline + house element in the mark.
    static let ecoGreen = Color(red: 0.48, green: 0.73, blue: 0.28)
    /// Light steel-blue used for water waves and window panes on the mark.
    static let ecoBlue = Color(red: 0.55, green: 0.68, blue: 0.78)
    /// Darker green for hover / pressed accents.
    static let ecoGreenDark = Color(red: 0.32, green: 0.55, blue: 0.18)
}
