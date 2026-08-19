import SwiftUI

struct ProfileTabView: View {
    @Environment(AuthManager.self) private var auth

    @State private var route: ProfileRoute?
    @State private var catalogBits: [Prompt] = []
    @State private var isLoadingBits = false
    @State private var bitsLoadError: String?
    @State private var showSignOutConfirm = false
    @State private var photoCount = 0
    @State private var answeredBitsCount = 0
    @State private var bitAnswers: [PromptAnswer] = []

    private let promptService = FirestorePromptService()

    private var completion: ProfileCompletion {
        ProfileCompletion(
            user: auth.currentUser,
            photoCount: photoCount,
            answeredBits: answeredBitsCount
        )
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            ScrollView {
                VStack(spacing: 16) {
                    topBar
                    header

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.danger)
                            .multilineTextAlignment(.center)
                    }

                    suggestionsCard
                    sectionsCard
                    missionCard
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
        }
        .sheet(item: $route) { route in
            sheet(for: route)
        }
        .confirmationDialog("Log out of NADA?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            async let bits: Void = loadBitsCatalog()
            async let photos: Void = refreshPhotoCount()
            async let answers: Void = refreshBitAnswers()
            _ = await (bits, photos, answers)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                route = .preview
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Preview profile")

            Spacer()

            Text("My Profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NADATheme.ink)

            Spacer()

            Button {
                route = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ProfileAvatarPicker(size: 120)

            VStack(spacing: 5) {
                Text(auth.currentUser?.displayName ?? "Your name")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(NADATheme.ink)

                if let city = auth.currentUser?.city, !city.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .medium))
                        Text(city)
                    }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                }
            }

            completionMeter
                .padding(.top, 4)

            actionButtons
                .padding(.top, 2)
        }
    }

    private var completionMeter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(completion.percentComplete)% complete")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NADATheme.warmSecondaryInk)

                Spacer()

                Text(auth.isProfileComplete ? "Ready for Discover" : "Finish for Discover")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        auth.isProfileComplete ? NADATheme.brand : NADATheme.secondaryInk
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NADATheme.brandSoft)

                    Capsule()
                        .fill(NADATheme.brand)
                        .frame(width: max(6, proxy.size.width * (Double(completion.percentComplete) / 100)))
                }
            }
            .frame(height: 5)
        }
        .animation(.easeOut(duration: 0.25), value: completion.percentComplete)
        .animation(.easeOut(duration: 0.25), value: auth.isProfileComplete)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                route = .preview
            } label: {
                Label {
                    Text("Preview profile")
                } icon: {
                    Image(systemName: "eye")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(NADASoftCapsuleButtonStyle())

            Button {
                auth.clearError()
                route = .edit
            } label: {
                Text("Edit")
            }
            .buttonStyle(NADADarkCapsuleButtonStyle())
            .frame(maxWidth: 124)
        }
    }

    @ViewBuilder
    private var suggestionsCard: some View {
        let suggestions = completion.suggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestions.count == 1 ? "Next step" : "Next steps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NADATheme.warmSecondaryInk)
                        .tracking(0.3)

                    Text("Make your profile feel more like you")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NADATheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            route = ProfileRoute(section: suggestion.section)
                        } label: {
                            ProfileSuggestionRow(suggestion: suggestion)
                        }
                        .buttonStyle(NADATactilePressStyle())
                        .accessibilityLabel(suggestion.title)
                        .accessibilityHint(suggestion.note)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .profileSurface()
        }
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NADATheme.ink)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(ProfileSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button {
                        route = ProfileRoute(section: section)
                    } label: {
                        ProfileSectionRow(
                            section: section,
                            detail: completion.detail(for: section),
                            isComplete: completion.progress(for: section) >= 1
                        )
                    }
                    .buttonStyle(ProfileSectionRowStyle())
                    .accessibilityLabel(section.title)
                    .accessibilityValue(completion.detail(for: section) ?? (completion.progress(for: section) >= 1 ? "Complete" : "Can be improved"))
                    .accessibilityHint("Opens the editor")

                    if index < ProfileSection.allCases.count - 1 {
                        Rectangle()
                            .fill(NADATheme.hairline.opacity(0.32))
                            .frame(height: 0.5)
                            .padding(.leading, 64)
                            .padding(.trailing, 16)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .profileSurface()
    }

    private var missionCard: some View {
        VStack(spacing: 6) {
            Text("NADA is for real connections.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NADATheme.ink)

            Text("We're building a safe, friendly space for people who just want to hang out.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)

            Image("SketchWelcomeHangout")
                .resizable()
                .scaledToFit()
                .frame(height: 88)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(NADATheme.brandSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var signOutButton: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 8) {
                Text("Log out")
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(NADATheme.brandPressed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheet(for route: ProfileRoute) -> some View {
        switch route {
        case .edit, .about:
            ProfileEditSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .settings:
            ProfileSettingsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .photos:
            ProfilePhotosSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    Task {
                        await auth.refreshCurrentUser()
                        await refreshPhotoCount()
                    }
                }
        case .bits:
            ProfileBitsSheet(
                initialBits: catalogBits,
                onAnswersChanged: {
                    Task { await refreshBitAnswers() }
                }
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    Task { await refreshBitAnswers() }
                }
        case .interests:
            ProfileInterestsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .location:
            ProfilePreferencesSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear {
                    Task { await auth.refreshPreferences() }
                }
        case .preview:
            ProfilePreviewSheet(bits: catalogBits, answers: bitAnswers)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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

    private func refreshPhotoCount() async {
        let photos = await auth.fetchPhotos()
        photoCount = photos.count
        if photoCount == 0, auth.currentUser?.photoURL?.isEmpty == false {
            photoCount = 1
        }
        if let avatarURL = auth.currentUser?.avatarURL {
            RemoteImageLoader.shared.prefetch(urlStrings: [avatarURL], targetPointSize: 120)
        }
    }

    private func refreshBitAnswers() async {
        bitAnswers = await auth.fetchBitAnswers()
        answeredBitsCount = bitAnswers.count
    }
}

#Preview {
    ProfileTabView()
        .environment(AuthManager())
}

private struct ProfileSuggestionRow: View {
    let suggestion: ProfileSuggestion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(NADATheme.brandSoft.opacity(0.85))
                Image(systemName: suggestion.section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NADATheme.brand)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
                    .multilineTextAlignment(.leading)

                Text(suggestion.note)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NADATheme.brand.opacity(0.85))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NADATheme.surface.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileSectionRow: View {
    let section: ProfileSection
    let detail: String?
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? NADATheme.surface.opacity(0.7) : NADATheme.brandSoft.opacity(0.8))
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isComplete ? NADATheme.warmSecondaryInk.opacity(0.9) : NADATheme.brand)
            }
            .frame(width: 34, height: 34)

            Text(section.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NADATheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if !isComplete {
                    Circle()
                        .fill(NADATheme.brand.opacity(0.9))
                        .frame(width: 4.5, height: 4.5)
                }

                if let detail {
                    Text(detail)
                        .font(.system(size: 13, weight: isComplete ? .regular : .medium))
                        .foregroundStyle(isComplete ? NADATheme.secondaryInk : NADATheme.brand)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(minWidth: 36, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NADATheme.secondaryInk.opacity(0.42))
                    .frame(width: 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }
}

private struct ProfileSectionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? NADATheme.surface.opacity(0.55) : Color.clear)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

private struct ProfileSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: NADATheme.ink.opacity(0.035), radius: 8, y: 3)
    }
}

private extension View {
    func profileSurface() -> some View {
        modifier(ProfileSurface())
    }
}
