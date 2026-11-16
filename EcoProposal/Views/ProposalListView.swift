import SwiftUI
import SwiftData

struct ProposalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Proposal.date, order: .reverse)]) private var proposals: [Proposal]
    @Binding var selection: Proposal?
    @Binding var showingSettings: Bool

    var body: some View {
        List(selection: $selection) {
            if CloudSync.shared.pendingUploads > 0 || !CloudSync.shared.conflicts.isEmpty {
                Section {
                    CloudUploadBanner()
                }
            }
            if proposals.isEmpty {
                ContentUnavailableView(
                    "No Proposals Yet",
                    systemImage: "doc.text",
                    description: Text("Tap + to create your first proposal.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Division.allCases) { division in
                    let list = proposals.filter { $0.division == division }
                    if !list.isEmpty {
                        Section {
                            ForEach(list) { proposal in
                                NavigationLink(value: proposal) {
                                    ProposalRow(proposal: proposal)
                                }
                            }
                            .onDelete { offsets in
                                deleteProposals(from: list, at: offsets)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: division.systemImage)
                                Text(division.displayName)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await CloudSync.shared.syncNow() }
        .navigationTitle("Proposals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(Division.allCases) { division in
                        Button {
                            addProposal(in: division)
                        } label: {
                            Label(division.displayName, systemImage: division.systemImage)
                        }
                    }
                } label: {
                    Label("New Proposal", systemImage: "plus")
                }
            }
        }
    }

    private func addProposal(in division: Division) {
        let company = CompanyInfo.load()
        let proposal = Proposal(
            // Signed in to EcoProposal Cloud: the database assigns the number on upload.
            proposalNumber: CloudSync.shared.isActive ? "" : CompanyInfo.nextProposalNumber(),
            date: Date(),
            status: .draft,
            division: division,
            taxRate: company.defaultTaxRate,
            terms: company.defaultTerms
        )
        modelContext.insert(proposal)
        try? modelContext.save()
        selection = proposal
    }

    private func deleteProposals(from list: [Proposal], at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                // Cloud proposals are deleted on the website (they'd come back on the next sync).
                guard !CloudSyncState.shared.isCloudProposal(list[index].id) else { continue }
                modelContext.delete(list[index])
            }
        }
    }
}

private struct ProposalRow: View {
    let proposal: Proposal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(proposal.proposalNumber.isEmpty ? "Number pending" : proposal.proposalNumber)
                    .font(.headline)
                if proposal.isArchived {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if proposal.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.ecoGreen)
                        .font(.caption)
                }
                if CloudSyncState.shared.isCloudProposal(proposal.id) {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(Color.ecoBlue)
                        .font(.caption)
                        .accessibilityLabel("Synced from EcoProposal Cloud")
                }
                Spacer()
                if proposal.isArchived {
                    Text("ARCHIVED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                } else {
                    StatusBadge(status: proposal.status)
                }
            }
            Text(proposal.job?.customer?.displayName ?? "No customer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                Text(proposal.date, style: .date)
                Spacer()
                Text(proposal.total, format: .currency(code: "USD"))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(proposal.isArchived ? 0.65 : 1.0)
    }
}

struct StatusBadge: View {
    let status: ProposalStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case .draft:    return Color.gray.opacity(0.2)
        case .sent:     return Color.blue.opacity(0.15)
        case .accepted: return Color.ecoGreen.opacity(0.2)
        case .declined: return Color.red.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch status {
        case .draft:    return .gray
        case .sent:     return .blue
        case .accepted: return .ecoGreen
        case .declined: return .red
        }
    }
}
