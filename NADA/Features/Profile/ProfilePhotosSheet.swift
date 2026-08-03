import PhotosUI
import SwiftUI
import UIKit

/// Up to 6 ordered profile photos with multi-select upload, sequential crop, primary / delete / reorder.
struct ProfilePhotosSheet: View {
    @Environment(AuthManager.self) private var auth

    @State private var photos: [ProfilePhoto] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var localError: String?
    @State private var selectedPhoto: ProfilePhoto?

    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isLibraryPresented = false

    /// Remaining images waiting to be framed after the one currently in the editor.
    @State private var cropQueue: [UIImage] = []
    @State private var isEditorPresented = false
    @State private var editorImage: UIImage?
    @State private var editorImageID = UUID()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var remainingSlots: Int {
        max(0, ProfilePhoto.maxCount - photos.count)
    }

    /// Square crop only while there is still no primary photo yet.
    private var editorAspect: CGFloat {
        photos.isEmpty
            ? ProfilePhotoAspect.primary
            : ProfilePhotoAspect.gallery
    }

    private var editorSubtitle: String? {
        if photos.isEmpty {
            return cropQueue.isEmpty
                ? "Frame your main photo"
                : "Main photo · \(cropQueue.count) more after this"
        }
        if cropQueue.isEmpty { return "Frame this photo" }
        return "\(cropQueue.count) more after this"
    }

    var body: some View {
        ProfileSheetScaffold(title: "Photos") {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(photos.count) of \(ProfilePhoto.maxCount) photos")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                Text("You can select several photos at once (up to your remaining slots) and frame each one in order. Your main photo is square; the rest use a 3:4 portrait frame.")
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

                        if remainingSlots > 0 {
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
            selection: $libraryItems,
            maxSelectionCount: max(remainingSlots, 1),
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await enqueuePickedItems(items) }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            if let editorImage {
                ProfilePhotoCropView(
                    source: editorImage,
                    aspectWidthOverHeight: editorAspect,
                    subtitle: editorSubtitle,
                    onCancel: { cancelCropQueue() },
                    onCrop: { cropped in
                        Task { await addCroppedAndContinue(cropped) }
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
            libraryItems = []
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
            .aspectRatio(
                photos.isEmpty ? ProfilePhotoAspect.primary : ProfilePhotoAspect.gallery,
                contentMode: .fit
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving || auth.isBusy || isEditorPresented)
        .accessibilityLabel("Add photos")
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
                .aspectRatio(
                    photo.isPrimary ? ProfilePhotoAspect.primary : ProfilePhotoAspect.gallery,
                    contentMode: .fit
                )
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

    // MARK: - Data

    private func reload() async {
        isLoading = true
        localError = nil
        defer { isLoading = false }
        photos = await auth.fetchPhotos()
    }

    private func enqueuePickedItems(_ items: [PhotosPickerItem]) async {
        let capped = Array(items.prefix(remainingSlots))
        libraryItems = []

        var images: [UIImage] = []
        for item in capped {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                localError = "Couldn't load one of the selected photos."
                continue
            }
            images.append(image)
        }

        guard let first = images.first else { return }
        cropQueue = Array(images.dropFirst())
        editorImage = first
        editorImageID = UUID()
        isEditorPresented = true
    }

    private func presentNextInQueue() {
        guard let next = cropQueue.first else {
            closeEditor()
            return
        }
        cropQueue.removeFirst()
        editorImage = next
        editorImageID = UUID()
        isEditorPresented = true
    }

    private func closeEditor() {
        isEditorPresented = false
        editorImage = nil
        cropQueue = []
        libraryItems = []
    }

    private func cancelCropQueue() {
        closeEditor()
    }

    private func addCroppedAndContinue(_ image: UIImage) async {
        isSaving = true
        localError = nil
        defer { isSaving = false }

        if let added = await auth.addPhoto(image) {
            photos.append(added)
            photos.sort { $0.sortOrder < $1.sortOrder }
            photos = await auth.fetchPhotos()
            presentNextInQueue()
        } else {
            if auth.errorMessage == nil {
                localError = "Couldn't add that photo."
            }
            closeEditor()
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

private enum ProfilePhotoAspect {
    static let primary: CGFloat = 1
    static let gallery: CGFloat = 3.0 / 4.0
}
