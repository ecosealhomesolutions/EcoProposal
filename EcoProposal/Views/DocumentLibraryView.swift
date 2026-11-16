import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings screen for managing the shared literature library. Reps import PDFs
/// once here (brochures, spec sheets, warranty docs); they can then be attached to
/// any proposal from the editor's Literature section.
struct DocumentLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryDocument.title) private var documents: [LibraryDocument]

    @State private var showingImporter = false
    @State private var importError: String?
    @State private var renamingDocument: LibraryDocument?
    @State private var previewingDocument: LibraryDocument?

    var body: some View {
        List {
            if documents.isEmpty {
                Section {
                    Text("No documents yet. Add PDFs you send often — they'll be available to attach to any proposal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(documents) { document in
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
                                        Text(document.filename)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                renamingDocument = document
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Add document", systemImage: "doc.badge.plus")
                }
            } footer: {
                if let importError {
                    Text(importError).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Document library")
        .iosInlineNavigationTitle()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $renamingDocument) { document in
            RenameDocumentSheet(document: document)
        }
        .sheet(item: $previewingDocument) { document in
            DocumentPreviewSheet(title: document.title, data: document.pdfData)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    importError = "Couldn't read \(url.lastPathComponent)."
                    continue
                }
                let name = url.deletingPathExtension().lastPathComponent
                let document = LibraryDocument(title: name, filename: url.lastPathComponent, pdfData: data)
                modelContext.insert(document)
            }
            try? modelContext.save()
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
        try? modelContext.save()
    }
}

private struct RenameDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: LibraryDocument

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document title", text: $document.title)
                }
                Section {
                    Text(document.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("File")
                }
            }
            .navigationTitle("Rename document")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
