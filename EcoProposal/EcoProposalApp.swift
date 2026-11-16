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
            // Phase-1 fallback: schema changed and the on-disk store is incompatible.
            // Wipe the old store files and rebuild so the app can launch. Fine for a
            // pre-production tool with no valuable local data yet — will be replaced
            // with a proper VersionedSchema migration once we ship to reps.
            print("SwiftData: rebuilding container after schema mismatch — \(error)")
            deleteExistingStore(for: configuration)
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
                ContentView()
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

/// Removes the SwiftData store files at the configuration's URL so a fresh container can be created.
/// SwiftData writes `.store`, `.store-wal`, and `.store-shm` alongside the primary file.
private func deleteExistingStore(for configuration: ModelConfiguration) {
    let baseURL = configuration.url
    let candidates = [
        baseURL,
        baseURL.appendingPathExtension("wal"),
        baseURL.appendingPathExtension("shm"),
    ]
    for url in candidates {
        try? FileManager.default.removeItem(at: url)
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
