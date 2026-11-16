import SwiftUI
import SwiftData

/// Sidebar list of Service Reports (jobsite condition assessments).
struct InspectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\InspectionReport.visitDate, order: .reverse)])
    private var reports: [InspectionReport]
    @Binding var selection: InspectionReport?
    @Binding var showingSettings: Bool

    var body: some View {
        List(selection: $selection) {
            if reports.isEmpty {
                ContentUnavailableView(
                    "No Inspection Reports",
                    systemImage: "checklist.checked",
                    description: Text("Tap + to start a jobsite condition assessment.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(reports) { report in
                    NavigationLink(value: report) {
                        InspectionRow(report: report)
                    }
                }
                .onDelete(perform: deleteReports)
            }
        }
        .navigationTitle("Inspections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addReport()
                } label: {
                    Label("New Inspection Report", systemImage: "plus")
                }
            }
        }
    }

    private func addReport() {
        let report = InspectionReport(reportNumber: InspectionReport.nextReportNumber())
        modelContext.insert(report)
        try? modelContext.save()
        selection = report
    }

    private func deleteReports(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(reports[index])
            }
        }
    }
}

private struct InspectionRow: View {
    let report: InspectionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(report.reportNumber)
                    .font(.headline)
                Spacer()
                if report.techSignatureData != nil {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.ecoGreen)
                        .font(.caption)
                }
            }
            Text(report.homeowner.isEmpty ? "No homeowner" : report.homeowner)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                Text(report.visitDate, style: .date)
                Spacer()
                if !report.jobNumber.isEmpty {
                    Text("Job # \(report.jobNumber)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
