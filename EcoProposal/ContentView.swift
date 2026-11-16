import SwiftUI
import SwiftData

struct ContentView: View {
    enum SidebarMode: String, CaseIterable, Identifiable {
        case proposals
        case inspections

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .proposals:   return "Proposals"
            case .inspections: return "Inspections"
            }
        }
    }

    @State private var mode: SidebarMode = .proposals
    @State private var selection: Proposal?
    @State private var inspectionSelection: InspectionReport?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Section", selection: $mode) {
                    ForEach(SidebarMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch mode {
                case .proposals:
                    ProposalListView(selection: $selection, showingSettings: $showingSettings)
                case .inspections:
                    InspectionListView(selection: $inspectionSelection, showingSettings: $showingSettings)
                }
            }
        } detail: {
            switch mode {
            case .proposals:
                if let proposal = selection {
                    NavigationStack {
                        ProposalEditorView(proposal: proposal) { newVersion in
                            selection = newVersion
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Proposal",
                        systemImage: "doc.text",
                        description: Text("Pick a proposal from the sidebar, or tap + to create one.")
                    )
                }
            case .inspections:
                if let report = inspectionSelection {
                    NavigationStack {
                        InspectionEditorView(report: report)
                    }
                } else {
                    ContentUnavailableView(
                        "Select an Inspection Report",
                        systemImage: "checklist.checked",
                        description: Text("Pick a report from the sidebar, or tap + to start one.")
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Customer.self, Job.self, Proposal.self, LineItem.self, JobPhoto.self, Blueprint.self, BlueprintPage.self], inMemory: true)
        .tint(.ecoGreen)
}
