import SwiftUI
import SwiftData
import PhotosUI

/// Photo capture for inspection reports — same flow as the proposal PhotosSection
/// (library picker + camera, caption, pencil markup) but parented to the report.
struct InspectionPhotosSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var report: InspectionReport
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var loadError: String?

    private let thumbSize: CGFloat = 110
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var sortedPhotos: [JobPhoto] {
        report.photos.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section {
            if sortedPhotos.isEmpty {
                Text("No photos yet. Use the buttons below to document the jobsite conditions.")
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
                Text("Photos are appended to the report PDF, one per page.")
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
        let nextSort = (report.photos.map(\.sortOrder).max() ?? -1) + 1
        let photo = JobPhoto(imageData: data, sortOrder: nextSort)
        photo.inspection = report
        modelContext.insert(photo)
        report.photos.append(photo)
        // Taking a photo answers the form's "Photos taken" box.
        report.photosTaken = true
        try? modelContext.save()
    }

    private func delete(_ photo: JobPhoto) {
        modelContext.delete(photo)
        try? modelContext.save()
    }
}
