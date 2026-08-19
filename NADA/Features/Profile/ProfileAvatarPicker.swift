import PhotosUI
import SwiftUI
import UIKit

/// Read-only circular avatar backed by the stored thumbnail (or display URL).
struct ProfileAvatarImage: View {
    let urlString: String?
    var size: CGFloat = 128
    var localImage: Image?

    var body: some View {
        ZStack {
            Circle()
                .fill(NADATheme.brandSoft)

            content
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        if let localImage {
            localImage
                .resizable()
                .scaledToFill()
        } else if let urlString {
            RemoteImageView(
                urlString: urlString,
                targetPointSize: size
            )
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(NADATheme.brand)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NADATheme.brandSoft)
    }
}

/// Tapping opens the crop editor for the current photo, or the library when there is none.
struct ProfileAvatarPicker: View {
    @Environment(AuthManager.self) private var auth

    var size: CGFloat = 132

    @State private var libraryItem: PhotosPickerItem?
    @State private var replacementItem: PhotosPickerItem?
    @State private var isLibraryPresented = false
    @State private var isReplacePresented = false
    @State private var isEditorPresented = false
    @State private var editorImage: UIImage?
    @State private var editorImageID = UUID()
    @State private var localAvatar: Image?
    @State private var isUploading = false
    @State private var isPreparing = false

    private var badgeSize: CGFloat { max(30, size * 0.24) }

    var body: some View {
        Button {
            Task { await openEditor() }
        } label: {
            avatarLabel
        }
        .buttonStyle(.plain)
        .disabled(isUploading || isPreparing || auth.isBusy)
        .accessibilityLabel("Edit profile photo")
        .photosPicker(
            isPresented: $isLibraryPresented,
            selection: $libraryItem,
            matching: PickerImageLoader.stillPhotosFilter,
            photoLibrary: .shared()
        )
        .onChange(of: libraryItem) { _, item in
            Task { await presentEditor(with: item, clearing: { libraryItem = nil }) }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            editorContent
        }
    }

    private var avatarLabel: some View {
        let photoURL = auth.currentUser?.avatarURL
        let currentAvatar = localAvatar

        return ZStack {
            ProfileAvatarImage(
                urlString: photoURL,
                size: size,
                localImage: currentAvatar
            )
            .id(photoURL ?? "empty-avatar")

            if isUploading || isPreparing {
                Circle()
                    .fill(NADATheme.ink.opacity(0.35))
                    .frame(width: size, height: size)
                ProgressView()
                    .tint(NADATheme.paper)
            }

            Circle()
                .strokeBorder(NADATheme.paper, lineWidth: 3)
                .frame(width: size, height: size)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    cameraBadge
                }
            }
            .frame(width: size, height: size)
        }
        .onChange(of: auth.currentUser?.avatarURL) { _, _ in
            // Drop optimistic local preview when the server primary URL changes (e.g. reorder).
            localAvatar = nil
        }
    }

    private var cameraBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: badgeSize * 0.42, weight: .semibold))
            .foregroundStyle(NADATheme.onBrand)
            .frame(width: badgeSize, height: badgeSize)
            .background(NADATheme.brand, in: Circle())
            .overlay(Circle().strokeBorder(NADATheme.paper, lineWidth: 2.5))
    }

    @ViewBuilder
    private var editorContent: some View {
        if let editorImage {
            ProfilePhotoCropView(
                source: editorImage,
                onCancel: { closeEditor() },
                onReplace: { isReplacePresented = true },
                onCrop: { cropped in
                    closeEditor()
                    Task { await upload(cropped) }
                }
            )
            .id(editorImageID)
            .photosPicker(
                isPresented: $isReplacePresented,
                selection: $replacementItem,
                matching: PickerImageLoader.stillPhotosFilter,
                photoLibrary: .shared()
            )
            .onChange(of: replacementItem) { _, item in
                Task { await replaceEditorImage(with: item) }
            }
        }
    }

    /// Existing photo → crop editor. No photo yet → library, then the same editor.
    private func openEditor() async {
        auth.clearError()

        guard auth.currentUser?.avatarURL?.isEmpty == false else {
            isLibraryPresented = true
            return
        }

        isPreparing = true
        let current = await currentPhotoImage()
        isPreparing = false

        if let current {
            editorImage = current
            editorImageID = UUID()
            isEditorPresented = true
        } else {
            isLibraryPresented = true
        }
    }

    private func presentEditor(with item: PhotosPickerItem?, clearing: @escaping () -> Void) async {
        guard let item else { return }
        isPreparing = true
        let image = await loadImage(from: item)
        isPreparing = false
        clearing()

        guard let image else { return }
        editorImage = image
        editorImageID = UUID()
        isEditorPresented = true
    }

    private func replaceEditorImage(with item: PhotosPickerItem?) async {
        guard let item else { return }
        let image = await loadImage(from: item)
        replacementItem = nil

        guard let image else { return }
        editorImage = image
        editorImageID = UUID()
    }

    private func closeEditor() {
        isEditorPresented = false
        editorImage = nil
        libraryItem = nil
        replacementItem = nil
    }

    private func loadImage(from item: PhotosPickerItem) async -> UIImage? {
        await PickerImageLoader.load(item)
    }

    private func currentPhotoImage() async -> UIImage? {
        await RemoteImageLoader.shared.image(
            urlString: auth.currentUser?.photoURL,
            targetPointSize: ImageIOCodec.displayMaxPixelSize
        )
    }

    private func upload(_ image: UIImage) async {
        localAvatar = Image(uiImage: image)
        isUploading = true
        auth.clearError()
        let ok = await auth.uploadProfilePhoto(image)
        isUploading = false
        if ok {
            localAvatar = nil
        }
    }
}
