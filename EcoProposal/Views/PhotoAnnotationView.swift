import SwiftUI
import SwiftData

/// Full-sheet editor: the source photo displayed at fit-to-screen with a
/// transparent PencilKit canvas on top. Anything the rep draws is stored as
/// `PKDrawing` bytes on `JobPhoto.annotationData` and rendered on top of the
/// photo when the PDF is generated.
struct PhotoAnnotationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var photo: JobPhoto

    @State private var draftInk: Data?

    init(photo: JobPhoto) {
        self.photo = photo
        _draftInk = State(initialValue: photo.annotationData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let img = PlatformImage.image(from: photo.imageData) {
                    ZStack {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        // PencilKit sits on top of the photo. `.clear` background
                        // lets the photo show through the ink.
                        DrawingCanvas(data: $draftInk)
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("Couldn't decode this photo.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Annotate Photo")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .leadingCompat) {
                    Button(role: .destructive) {
                        draftInk = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(draftInk == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func save() {
        photo.annotationData = draftInk
        photo.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
