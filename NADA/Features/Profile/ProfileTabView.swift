import PhotosUI
import SwiftUI
import UIKit

struct ProfileTabView: View {
    @Environment(AuthManager.self) private var auth

    @State private var isEditing = false
    @State private var showSettings = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var localAvatar: Image?
    @State private var isUploadingPhoto = false
    @State private var catalogBits: [Prompt] = []
    @State private var bitsLoadError: String?
    @State private var isLoadingBits = false

    private let promptService = FirestorePromptService()

    var body: some View {
        ZStack {
            NADAScreenBackground()

            ScrollView {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 16) {
                        avatarPicker

                        Text(auth.currentUser?.displayName ?? "Your name")
                            .font(NADATheme.titleFont)
                            .foregroundStyle(NADATheme.ink)
                            .multilineTextAlignment(.center)

                        if let error = auth.errorMessage, isUploadingPhoto == false {
                            Text(error)
                                .font(NADATheme.captionFont)
                                .foregroundStyle(.red.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }

                        Button("Edit profile") {
                            auth.clearError()
                            isEditing = true
                        }
                        .buttonStyle(NADACapsulePrimaryButtonStyle())
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                    if let user = auth.currentUser {
                        profileMeta(user)
                            .padding(.horizontal, 28)
                            .padding(.top, 28)
                    }

                    bitsCatalogSection
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                        .padding(.bottom, 36)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            ProfileSettingsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await uploadPhoto(from: newItem) }
        }
        .task {
            await auth.refreshCurrentUser()
            await loadBitsCatalog()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image("SplashMark")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityLabel("NADA")

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
                    .frame(width: 36, height: 36)
                    .background(NADATheme.surface, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(NADATheme.brandSoft)
                    .frame(width: 128, height: 128)

                avatarContent
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())

                if isUploadingPhoto {
                    Circle()
                        .fill(NADATheme.ink.opacity(0.35))
                        .frame(width: 128, height: 128)
                    ProgressView()
                        .tint(NADATheme.paper)
                }

                Circle()
                    .strokeBorder(NADATheme.paper, lineWidth: 4)
                    .frame(width: 128, height: 128)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NADATheme.onBrand)
                            .frame(width: 32, height: 32)
                            .background(NADATheme.brand, in: Circle())
                            .overlay(Circle().strokeBorder(NADATheme.paper, lineWidth: 3))
                    }
                }
                .frame(width: 128, height: 128)
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingPhoto || auth.isBusy)
        .accessibilityLabel("Upload profile photo")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let localAvatar {
            localAvatar
                .resizable()
                .scaledToFill()
        } else if let urlString = auth.currentUser?.photoURL,
                  let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderAvatar
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholderAvatar
                }
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 48, weight: .medium))
            .foregroundStyle(NADATheme.brand)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NADATheme.brandSoft)
    }

    private func profileMeta(_ user: NADAUser) -> some View {
        VStack(spacing: 10) {
            if let email = user.email {
                Text(email)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            HStack(spacing: 16) {
                if let gender = ProfileGender.fromStored(user.gender)?.title {
                    Label(gender, systemImage: "person")
                }
                if let city = user.city, !city.isEmpty {
                    Label(city, systemImage: "mappin")
                }
            }
            .font(NADATheme.captionFont)
            .foregroundStyle(NADATheme.warmSecondaryInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var bitsCatalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bits")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            Text("Questions you can answer on your profile. Answering comes in Week 2.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            if isLoadingBits {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if let bitsLoadError {
                Text(bitsLoadError)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(.red.opacity(0.85))
            } else if catalogBits.isEmpty {
                Text("No bits in the catalog yet. Seed `prompts` in Firestore.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(catalogBits) { bit in
                        Text(bit.text)
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadBitsCatalog() async {
        isLoadingBits = true
        bitsLoadError = nil
        defer { isLoadingBits = false }

        do {
            catalogBits = try await promptService.fetchActivePrompts(locale: "en")
        } catch {
            bitsLoadError = "Couldn't load bits. Check Firestore rules and seed."
            catalogBits = []
        }
    }

    private func uploadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        localAvatar = Image(uiImage: uiImage)
        isUploadingPhoto = true
        auth.clearError()
        let ok = await auth.uploadProfilePhoto(uiImage)
        isUploadingPhoto = false
        if ok {
            localAvatar = nil
            selectedPhoto = nil
        }
    }
}

/// Narrow coral capsule used under the avatar (not full-width primary CTA).
struct NADACapsulePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.onBrand)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? NADATheme.brandPressed : NADATheme.brand)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct ProfileSettingsSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NADATheme.paper.ignoresSafeArea()

                VStack(spacing: 16) {
                    Button {
                        dismiss()
                        auth.signOut()
                    } label: {
                        Text("Sign out")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NADASecondaryButtonStyle())

                    Text("More settings coming soon.")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
            }
        }
    }
}

private struct ProfileEditSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var city = ""
    @State private var gender: ProfileGender?
    @State private var localError: String?
    @State private var didSave = false

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gender != nil
            && !auth.isBusy
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NADATheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Keep these up to date so hangouts feel personal.")
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.warmSecondaryInk)

                        ProfileBasicsForm(
                            displayName: $displayName,
                            city: $city,
                            gender: $gender,
                            errorMessage: localError ?? auth.errorMessage
                        )

                        if didSave {
                            Text("Saved.")
                                .font(NADATheme.captionFont)
                                .foregroundStyle(NADATheme.brandPressed)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            if auth.isBusy {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save")
                            }
                        }
                        .buttonStyle(NADAPrimaryButtonStyle())
                        .disabled(!canSave)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
            }
            .onAppear {
                auth.clearError()
                displayName = auth.currentUser?.displayName ?? ""
                city = auth.currentUser?.city ?? ""
                gender = ProfileGender.fromStored(auth.currentUser?.gender)
            }
        }
    }

    private func save() async {
        localError = nil
        didSave = false
        guard let gender else {
            localError = "Please select a gender option."
            return
        }

        let ok = await auth.updateBasicProfile(
            displayName: displayName,
            gender: gender,
            city: city
        )
        if ok {
            didSave = true
            dismiss()
        } else if auth.errorMessage == nil {
            localError = "Couldn't save your profile. Try again."
        }
    }
}

#Preview {
    ProfileTabView()
        .environment(AuthManager())
}
