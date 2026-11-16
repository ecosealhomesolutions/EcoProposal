import SwiftUI
import SwiftData
import PhotosUI

struct PhotosSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var proposal: Proposal
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var loadError: String?

    private let thumbSize: CGFloat = 110
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var sortedPhotos: [JobPhoto] {
        proposal.photos.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section {
            if sortedPhotos.isEmpty {
                Text("No photos yet. Use the buttons below to add job-site photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedPhotos) { photo in
                        PhotoThumbnail(photo: photo, size: thumbSize) {
                            delete(photo)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 0,      // 0 = unlimited
                    matching: .images
                ) {
                    Label("From library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                if CameraAvailability.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                Text("Photos are appended to the PDF, one per page.")
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await load(newItems) }
        }
        .sheet(isPresented: $showingCamera) {
            #if os(iOS)
            CameraPicker { data in
                addPhoto(data: data)
            }
            .ignoresSafeArea()
            #endif
        }
    }

    // MARK: - Actions

    @MainActor
    private func load(_ items: [PhotosPickerItem]) async {
        loadError = nil
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    addPhoto(data: data)
                }
            } catch {
                loadError = "Couldn't load photo: \(error.localizedDescription)"
            }
        }
        pickerItems.removeAll()
    }

    private func addPhoto(data: Data) {
        let nextSort = (proposal.photos.map(\.sortOrder).max() ?? -1) + 1
        let photo = JobPhoto(imageData: data, sortOrder: nextSort, proposal: proposal)
        modelContext.insert(photo)
        proposal.photos.append(photo)
        try? modelContext.save()
    }

    private func delete(_ photo: JobPhoto) {
        modelContext.delete(photo)
        try? modelContext.save()
    }
}

// Shared with InspectionPhotosSection — any JobPhoto works regardless of parent.
struct PhotoThumbnail: View {
    let photo: JobPhoto
    let size: CGFloat
    var onDelete: () -> Void
    @State private var showingCaptionEditor = false
    @State private var showingAnnotator = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Button {
                    showingAnnotator = true
                } label: {
                    ZStack(alignment: .topLeading) {
                        if let image = PlatformImage.image(from: photo.imageData) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(white: 0.85), lineWidth: 0.5)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(white: 0.92))
                                .frame(width: size, height: size)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                        // Tiny badge shows a marker was drawn.
                        if photo.annotationData != nil {
                            Image(systemName: "pencil.tip.crop.circle.badge.plus")
                                .foregroundStyle(.white, Color.ecoGreen)
                                .symbolRenderingMode(.palette)
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Button {
                    showingCaptionEditor = true
                } label: {
                    Text(photo.caption.isEmpty ? "Add caption…" : photo.caption)
                        .font(.caption)
                        .foregroundStyle(photo.caption.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .frame(width: size)
            Button {
                showingAnnotator = true
            } label: {
                Label(photo.annotationData == nil ? "Annotate" : "Edit markup",
                      systemImage: "pencil.tip")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingCaptionEditor) {
            CaptionEditor(photo: photo)
        }
        .sheet(isPresented: $showingAnnotator) {
            PhotoAnnotationView(photo: photo)
        }
    }
}

struct CaptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var photo: JobPhoto

    var body: some View {
        NavigationStack {
            Form {
                if let image = PlatformImage.image(from: photo.imageData) {
                    image.resizable().scaledToFit().frame(maxHeight: 300)
                }
                Section("Caption") {
                    TextField("Describe this photo", text: $photo.caption, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Photo caption")
            .iosInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        photo.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
