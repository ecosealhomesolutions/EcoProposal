import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Editor section for attaching job-related literature (brochures, spec sheets, etc.)
/// to a proposal. Reps can pull from the shared library or import a one-off PDF.
/// Attached documents are merged onto the end of the generated proposal PDF.
struct LiteratureSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var proposal: Proposal

    @State private var showingImporter = false
    @State private var showingLibraryPicker = false
    @State private var importError: String?
    @State private var previewingDocument: ProposalDocument?

    private var sortedDocuments: [ProposalDocument] {
        proposal.documents.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section {
            if sortedDocuments.isEmpty {
                Text("No literature attached. Add brochures or spec sheets to send with this proposal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedDocuments) { document in
                    HStack(spacing: 12) {
                        // Tap the row to preview the PDF.
                        Button {
                            previewingDocument = document
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(Color.ecoNavy)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if document.filename != document.title {
                                        Text(document.filename)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            delete(document)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    showingLibraryPicker = true
                } label: {
                    Label("From library", systemImage: "books.vertical")
                }
                .buttonStyle(.bordered)

                Button {
                    showingImporter = true
                } label: {
                    Label("Attach document", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Literature")
        } footer: {
            if let importError {
                Text(importError).foregroundStyle(.red)
            } else {
                Text("Attached PDFs are added to the end of the proposal PDF and sent along with it.")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingLibraryPicker) {
            LibraryDocumentPicker { libraryDoc in
                attachFromLibrary(libraryDoc)
            }
        }
        .sheet(item: $previewingDocument) { document in
            DocumentPreviewSheet(title: document.title, data: document.pdfData)
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            for url in urls {
                guard let data = readPDF(at: url) else {
                    importError = "Couldn't read \(url.lastPathComponent)."
                    continue
                }
                let name = url.deletingPathExtension().lastPathComponent
                attach(title: name, filename: url.lastPathComponent, data: data)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func attachFromLibrary(_ libraryDoc: LibraryDocument) {
        attach(title: libraryDoc.title, filename: libraryDoc.filename, data: libraryDoc.pdfData)
    }

    private func attach(title: String, filename: String, data: Data) {
        let nextSort = (proposal.documents.map(\.sortOrder).max() ?? -1) + 1
        let document = ProposalDocument(
            title: title,
            filename: filename,
            pdfData: data,
            sortOrder: nextSort,
            proposal: proposal
        )
        modelContext.insert(document)
        proposal.documents.append(document)
        proposal.updatedAt = Date()
        try? modelContext.save()
    }

    private func delete(_ document: ProposalDocument) {
        modelContext.delete(document)
        proposal.updatedAt = Date()
        try? modelContext.save()
    }

    /// Reads a security-scoped file (as returned by the document picker) into memory.
    private func readPDF(at url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

/// Sheet listing the shared literature library so a rep can pick a document to
/// attach to the current proposal.
private struct LibraryDocumentPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibraryDocument.title) private var documents: [LibraryDocument]
    let onPick: (LibraryDocument) -> Void
    @State private var previewingDocument: LibraryDocument?

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView {
                        Label("No library documents", systemImage: "books.vertical")
                    } description: {
                        Text("Add brochures and spec sheets in Settings → Document library, then attach them here.")
                    }
                } else {
                    List(documents) { document in
                        HStack(spacing: 12) {
                            Button {
                                onPick(document)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.richtext")
                                        .foregroundStyle(Color.ecoNavy)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(document.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(document.filename)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.ecoGreen)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Peek at the brochure before attaching it.
                            Button {
                                previewingDocument = document
                            } label: {
                                Image(systemName: "eye")
                                    .foregroundStyle(Color.ecoNavy)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .sheet(item: $previewingDocument) { document in
                        DocumentPreviewSheet(title: document.title, data: document.pdfData)
                    }
                }
            }
            .navigationTitle("Choose literature")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
