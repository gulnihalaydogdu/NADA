import PhotosUI
import SwiftUI
import UIKit

/// Up to 6 ordered profile photos with primary / delete / add via crop editor.
struct ProfilePhotosSheet: View {
    @Environment(AuthManager.self) private var auth

    @State private var photos: [ProfilePhoto] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var localError: String?
    @State private var selectedPhoto: ProfilePhoto?
    @State private var libraryItem: PhotosPickerItem?
    @State private var isLibraryPresented = false
    @State private var isEditorPresented = false
    @State private var editorImage: UIImage?
    @State private var editorImageID = UUID()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ProfileSheetScaffold(title: "Photos") {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(photos.count) of \(ProfilePhoto.maxCount) photos")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                Text("Add up to six. The primary photo is what friends see first on your profile.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                if isLoading && photos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(photos) { photo in
                            photoCell(photo)
                        }

                        if photos.count < ProfilePhoto.maxCount {
                            addCell
                        }
                    }
                }

                if let message = localError ?? auth.errorMessage {
                    Text(message)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }

                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task { await reload() }
        .photosPicker(
            isPresented: $isLibraryPresented,
            selection: $libraryItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: libraryItem) { _, item in
            Task { await openCrop(with: item) }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            if let editorImage {
                ProfilePhotoCropView(
                    source: editorImage,
                    onCancel: { closeEditor() },
                    onCrop: { cropped in
                        closeEditor()
                        Task { await addCropped(cropped) }
                    }
                )
                .id(editorImageID)
            }
        }
        .confirmationDialog(
            "Photo options",
            isPresented: Binding(
                get: { selectedPhoto != nil },
                set: { if !$0 { selectedPhoto = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let selectedPhoto {
                if !selectedPhoto.isPrimary {
                    Button("Set as primary") {
                        Task { await setPrimary(selectedPhoto.id) }
                    }
                }
                if let index = photos.firstIndex(where: { $0.id == selectedPhoto.id }), index > 0 {
                    Button("Move earlier") {
                        Task { await movePhoto(id: selectedPhoto.id, by: -1) }
                    }
                }
                if let index = photos.firstIndex(where: { $0.id == selectedPhoto.id }),
                   index < photos.count - 1 {
                    Button("Move later") {
                        Task { await movePhoto(id: selectedPhoto.id, by: 1) }
                    }
                }
                Button("Delete photo", role: .destructive) {
                    Task { await delete(selectedPhoto.id) }
                }
                Button("Cancel", role: .cancel) {
                    self.selectedPhoto = nil
                }
            }
        }
    }

    private var addCell: some View {
        Button {
            localError = nil
            auth.clearError()
            isLibraryPresented = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NADATheme.brandSoft)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(NADATheme.brand)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || auth.isBusy)
        .accessibilityLabel("Add photo")
    }

    private func photoCell(_ photo: ProfilePhoto) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = URL(string: photo.url) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .empty:
                                ProgressView()
                            default:
                                NADATheme.brandSoft
                            }
                        }
                    } else {
                        NADATheme.brandSoft
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if photo.isPrimary {
                    Text("Primary")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NADATheme.onBrand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NADATheme.brand, in: Capsule())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving || auth.isBusy)
        .accessibilityLabel(photo.isPrimary ? "Primary photo" : "Photo")
    }

    private func reload() async {
        isLoading = true
        localError = nil
        defer { isLoading = false }
        photos = await auth.fetchPhotos()
    }

    private func openCrop(with item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            libraryItem = nil
            localError = "Couldn't load that photo."
            return
        }
        libraryItem = nil
        editorImage = image
        editorImageID = UUID()
        isEditorPresented = true
    }

    private func closeEditor() {
        isEditorPresented = false
        editorImage = nil
        libraryItem = nil
    }

    private func addCropped(_ image: UIImage) async {
        isSaving = true
        localError = nil
        defer { isSaving = false }

        if let added = await auth.addPhoto(image) {
            photos.append(added)
            photos.sort { $0.sortOrder < $1.sortOrder }
            // Refresh to pick up primary/sort sync from server.
            photos = await auth.fetchPhotos()
        } else if auth.errorMessage == nil {
            localError = "Couldn't add that photo."
        }
    }

    private func setPrimary(_ id: String) async {
        selectedPhoto = nil
        isSaving = true
        defer { isSaving = false }
        if let updated = await auth.setPrimaryPhoto(id: id) {
            photos = updated
        }
    }

    private func delete(_ id: String) async {
        selectedPhoto = nil
        isSaving = true
        defer { isSaving = false }
        if let updated = await auth.deletePhoto(id: id) {
            photos = updated
        }
    }

    private func movePhoto(id: String, by delta: Int) async {
        selectedPhoto = nil
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + delta
        guard photos.indices.contains(newIndex) else { return }

        var ordered = photos.map(\.id)
        ordered.swapAt(index, newIndex)
        isSaving = true
        defer { isSaving = false }
        if let updated = await auth.reorderPhotos(orderedIds: ordered) {
            photos = updated
        }
    }
}
