import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Shared photo grid: multi-select upload, sequential crop, drag reorder (first = primary), ✕ replace.
struct ProfilePhotosEditor: View {
    @Environment(AuthManager.self) private var auth

    var showsHeaderCopy: Bool = true
    var onPhotosChanged: (([ProfilePhoto]) -> Void)? = nil
    /// When true after a delete, parent can block Continue / Done until a replacement is added.
    var onReplacementRequiredChanged: ((Bool) -> Void)? = nil

    @State private var photos: [ProfilePhoto] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var localError: String?

    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isLibraryPresented = false

    @State private var cropQueue: [UIImage] = []
    @State private var pendingCropped: [UIImage] = []
    @State private var isCommittingCrops = false
    @State private var isEditorPresented = false
    @State private var editorImage: UIImage?
    @State private var editorImageID = UUID()
    @State private var recropTarget: ProfilePhoto?
    @State private var isReplacePresented = false
    @State private var replacementItem: PhotosPickerItem?
    @State private var preparingPhotoId: String?

    @State private var draggingPhotoId: String?
    @State private var needsReplacement = false
    @State private var replacementIndex: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)
    private let gridImagePointSize: CGFloat = 220

    private var remainingSlots: Int {
        max(0, ProfilePhoto.maxCount - photos.count)
    }

    private var editorSubtitle: String? {
        if recropTarget != nil {
            return "Drag and pinch to recrop. Done saves this slot."
        }
        if photos.isEmpty {
            return cropQueue.isEmpty
                ? "Frame your main photo"
                : "Main photo · \(cropQueue.count) more after this"
        }
        if cropQueue.isEmpty { return "Frame this photo" }
        return "\(cropQueue.count) more after this"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeaderCopy {
                Text("\(photos.count) of \(ProfilePhoto.maxCount) photos")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                Text("Tap a photo to recrop it. Drag to change the order — the first one is your main. Tap ✕ to remove one; the next photo you add fills that same spot.")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            } else {
                Text("\(photos.count) / \(ProfilePhoto.maxCount)")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            if isLoading && photos.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
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
                HStack(spacing: 10) {
                    ProgressView()
                    Text(isCommittingCrops ? "Saving photos…" : "Saving…")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .onChange(of: isLibraryPresented) { _, presented in
            if !presented, needsReplacement, libraryItems.isEmpty, !isEditorPresented {
                localError = "Add a photo to fill that spot."
            }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            if let editorImage {
                ProfilePhotoCropView(
                    source: editorImage,
                    aspectWidthOverHeight: 1,
                    subtitle: editorSubtitle,
                    onCancel: { cancelCropQueue() },
                    onReplace: recropTarget == nil ? nil : { isReplacePresented = true },
                    onCrop: { cropped in
                        acceptCrop(cropped)
                    }
                )
                .id(editorImageID)
                .photosPicker(
                    isPresented: $isReplacePresented,
                    selection: $replacementItem,
                    matching: .images,
                    photoLibrary: .shared()
                )
                .onChange(of: replacementItem) { _, item in
                    Task { await replaceRecropSource(with: item) }
                }
            }
        }
    }

    // MARK: - Cells

    private var addCell: some View {
        Button {
            localError = nil
            auth.clearError()
            presentLibrary()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NADATheme.brandSoft)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1)
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                    Text("Add")
                        .font(NADATheme.captionFont.weight(.semibold))
                }
                .foregroundStyle(NADATheme.brand)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isCommittingCrops || auth.isBusy || isEditorPresented)
        .accessibilityLabel("Add a photo")
    }

    private func photoCell(_ photo: ProfilePhoto) -> some View {
        let isDragging = draggingPhotoId == photo.id
        let isPreparing = preparingPhotoId == photo.id

        return ZStack {
            RemoteImageView(
                urlString: photo.previewURL,
                targetPointSize: gridImagePointSize
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                Task { await beginRecrop(photo) }
            }

            if isPreparing {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NADATheme.ink.opacity(0.35))
                    .allowsHitTesting(false)
                ProgressView()
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if photo.isPrimary {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.94, green: 0.82, blue: 0.48),
                                Color(red: 0.76, green: 0.58, blue: 0.26)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await delete(photo.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .disabled(isSaving || isCommittingCrops || auth.isBusy || isPreparing)
            .accessibilityLabel("Delete photo")
        }
        .opacity(isDragging ? 0.55 : 1)
        .onDrag {
            draggingPhotoId = photo.id
            return NSItemProvider(object: photo.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: PhotoReorderDropDelegate(
                targetId: photo.id,
                photos: $photos,
                draggingPhotoId: $draggingPhotoId,
                onFinished: { orderedIds in
                    Task { await persistOrder(orderedIds) }
                }
            )
        )
        .disabled(isSaving || isCommittingCrops || auth.isBusy)
        .accessibilityLabel(photo.isPrimary ? "Primary photo" : "Photo")
        .accessibilityHint("Tap to recrop. Drag to reorder.")
    }

    // MARK: - Data

    private func presentLibrary() {
        libraryItems = []
        isLibraryPresented = true
    }

    private func notifyPhotosChanged() {
        onPhotosChanged?(photos)
    }

    private func setNeedsReplacement(_ value: Bool) {
        needsReplacement = value
        onReplacementRequiredChanged?(value)
    }

    private func reload() async {
        isLoading = true
        localError = nil
        defer { isLoading = false }
        photos = await auth.fetchPhotos()
        notifyPhotosChanged()
        RemoteImageLoader.shared.prefetch(
            urlStrings: photos.map(\.previewURL),
            targetPointSize: gridImagePointSize
        )
    }

    private func enqueuePickedItems(_ items: [PhotosPickerItem]) async {
        let capped = Array(items.prefix(max(remainingSlots, 1)))
        libraryItems = []

        var images: [UIImage] = []
        for item in capped {
            guard let image = await PickerImageLoader.load(item) else {
                localError = "Couldn't load one of the selected photos."
                continue
            }
            images.append(image)
        }

        guard let first = images.first else { return }
        recropTarget = nil
        pendingCropped = []
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
    }

    private func closeEditor() {
        isEditorPresented = false
        editorImage = nil
        cropQueue = []
        pendingCropped = []
        libraryItems = []
        recropTarget = nil
        replacementItem = nil
        isReplacePresented = false
        preparingPhotoId = nil
    }

    private func cancelCropQueue() {
        closeEditor()
        if needsReplacement {
            localError = "Add a photo to fill that spot."
        }
    }

    /// Crop every picked photo first; upload only after the last Done.
    private func acceptCrop(_ image: UIImage) {
        guard !isCommittingCrops else { return }
        if let recropTarget {
            isEditorPresented = false
            editorImage = nil
            cropQueue = []
            pendingCropped = []
            libraryItems = []
            replacementItem = nil
            isReplacePresented = false
            Task { await commitRecrop(recropTarget, image: image) }
            return
        }

        pendingCropped.append(image)

        if cropQueue.isEmpty {
            let images = pendingCropped
            pendingCropped = []
            isEditorPresented = false
            editorImage = nil
            cropQueue = []
            libraryItems = []
            Task { await commitCroppedPhotos(images) }
        } else {
            presentNextInQueue()
        }
    }

    private func beginRecrop(_ photo: ProfilePhoto) async {
        guard !isSaving, !isCommittingCrops, !auth.isBusy, !isEditorPresented else { return }
        localError = nil
        auth.clearError()
        preparingPhotoId = photo.id
        var image = await RemoteImageLoader.shared.image(
            urlString: photo.url,
            targetPointSize: ImageIOCodec.displayMaxPixelSize
        )
        if image == nil {
            image = await RemoteImageLoader.shared.image(
                urlString: photo.previewURL,
                targetPointSize: ImageIOCodec.displayMaxPixelSize
            )
        }
        preparingPhotoId = nil
        guard let image else {
            localError = "Couldn't load that photo to edit."
            return
        }

        recropTarget = photo
        cropQueue = []
        pendingCropped = []
        editorImage = image
        editorImageID = UUID()
        isEditorPresented = true
    }

    private func replaceRecropSource(with item: PhotosPickerItem?) async {
        guard recropTarget != nil, let item else { return }
        let image = await PickerImageLoader.load(item)
        replacementItem = nil
        guard let image else {
            localError = "Couldn't load that photo."
            return
        }
        editorImage = image
        editorImageID = UUID()
    }

    private func commitRecrop(_ photo: ProfilePhoto, image: UIImage) async {
        guard !isCommittingCrops else { return }
        isCommittingCrops = true
        isSaving = true
        localError = nil
        defer {
            isCommittingCrops = false
            isSaving = false
            recropTarget = nil
        }

        if let updated = await auth.replacePhoto(id: photo.id, image: image) {
            photos = updated
            notifyPhotosChanged()
        } else if auth.errorMessage == nil {
            localError = "Couldn't update that photo."
        }
    }

    private func commitCroppedPhotos(_ images: [UIImage]) async {
        guard !images.isEmpty, !isCommittingCrops else { return }
        isCommittingCrops = true
        isSaving = true
        localError = nil
        defer {
            isCommittingCrops = false
            isSaving = false
        }

        let insertAt = needsReplacement ? replacementIndex : nil
        if let updated = await auth.addPhotos(images, startingAt: insertAt) {
            photos = updated
            if needsReplacement {
                setNeedsReplacement(false)
                replacementIndex = nil
            }
            notifyPhotosChanged()
        } else {
            if auth.errorMessage == nil {
                localError = "Couldn't add those photos."
            }
        }
    }

    private func delete(_ id: String) async {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }

        isSaving = true
        localError = nil
        defer { isSaving = false }

        if let updated = await auth.deletePhoto(id: id) {
            photos = updated
            replacementIndex = min(index, updated.count)
            setNeedsReplacement(true)
            localError = "Add a photo to fill that spot."
            notifyPhotosChanged()
            presentLibrary()
        }
    }

    private func persistOrder(_ orderedIds: [String]) async {
        applyLocalPrimary(from: orderedIds)
        notifyPhotosChanged()
        isSaving = true
        defer { isSaving = false }
        if let updated = await auth.reorderPhotos(orderedIds: orderedIds) {
            photos = updated
            notifyPhotosChanged()
        } else {
            photos = await auth.fetchPhotos()
            notifyPhotosChanged()
        }
    }

    private func applyLocalPrimary(from orderedIds: [String]) {
        let byId = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        photos = orderedIds.enumerated().compactMap { index, id in
            guard var photo = byId[id] else { return nil }
            photo.sortOrder = index
            photo.isPrimary = index == 0
            return photo
        }
    }
}

// MARK: - Sheet chrome

/// Profile → Photos sheet wrapping `ProfilePhotosEditor`.
struct ProfilePhotosSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var needsReplacement = false
    @State private var localError: String?

    private var canDismiss: Bool {
        !needsReplacement
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NADATheme.paper.ignoresSafeArea()

                ScrollView {
                    ProfilePhotosEditor(
                        showsHeaderCopy: true,
                        onReplacementRequiredChanged: { needsReplacement = $0 }
                    )
                    .padding(24)
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if canDismiss {
                            dismiss()
                        } else {
                            localError = "Add a photo to fill that spot."
                        }
                    }
                    .foregroundStyle(NADATheme.brandPressed)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let localError, needsReplacement {
                    Text(localError)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(NADATheme.paper)
                }
            }
        }
        .interactiveDismissDisabled(needsReplacement)
        .onChange(of: needsReplacement) { _, required in
            if !required { localError = nil }
        }
    }
}

// MARK: - Drag & drop reorder

struct PhotoReorderDropDelegate: DropDelegate {
    let targetId: String
    @Binding var photos: [ProfilePhoto]
    @Binding var draggingPhotoId: String?
    var onFinished: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingPhotoId,
              draggingPhotoId != targetId,
              let from = photos.firstIndex(where: { $0.id == draggingPhotoId }),
              let to = photos.firstIndex(where: { $0.id == targetId }),
              from != to else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            for index in photos.indices {
                photos[index].sortOrder = index
                photos[index].isPrimary = index == 0
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPhotoId = nil
        onFinished(photos.map(\.id))
        return true
    }

    func dropExited(info: DropInfo) {}
}
