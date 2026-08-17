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
                VStack(spacing: 20) {
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
                .padding(.top, 8)
                .padding(.bottom, 32)
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
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
            }
            .accessibilityLabel("Preview profile")

            Spacer()

            Text("My Profile")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            Spacer()

            Button {
                route = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(NADATheme.ink)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ProfileAvatarPicker(size: 132)

            VStack(spacing: 4) {
                Text(auth.currentUser?.displayName ?? "Your name")
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)

                if let city = auth.currentUser?.city, !city.isEmpty {
                    Label(city, systemImage: "mappin.and.ellipse")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.warmSecondaryInk)
                }
            }

            completionMeter
            actionButtons
        }
    }

    private var completionMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(completion.percentComplete)% complete")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)

                Spacer()

                Text(auth.isProfileComplete ? "Ready for Discover" : "Finish for Discover")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(
                        auth.isProfileComplete ? NADATheme.brandPressed : NADATheme.secondaryInk
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NADATheme.brandSoft)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NADATheme.brand, NADATheme.brandPressed],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * (Double(completion.percentComplete) / 100))
                }
            }
            .frame(height: 8)

            Text("Job, school, hangout looking-for, and interests add the last 10%.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
        }
        .animation(.easeOut(duration: 0.25), value: completion.percentComplete)
        .animation(.easeOut(duration: 0.25), value: auth.isProfileComplete)
        .padding(.top, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                route = .preview
            } label: {
                Label("Preview profile", systemImage: "eye")
            }
            .buttonStyle(NADASoftCapsuleButtonStyle())

            Button {
                auth.clearError()
                route = .edit
            } label: {
                Text("Edit")
            }
            .buttonStyle(NADADarkCapsuleButtonStyle())
            .frame(maxWidth: 140)
        }
    }

    @ViewBuilder
    private var suggestionsCard: some View {
        let suggestions = completion.suggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Make your profile feel more like you")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.brandPressed)

                ForEach(suggestions) { suggestion in
                    Button {
                        route = ProfileRoute(section: suggestion.section)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.section.systemImage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .frame(width: 22)

                            Text(suggestion.title)
                                .font(NADATheme.bodyFont)
                                .foregroundStyle(NADATheme.ink)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 8)

                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(NADATheme.brand)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your profile")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            VStack(spacing: 0) {
                ForEach(Array(ProfileSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button {
                        route = ProfileRoute(section: section)
                    } label: {
                        sectionRow(section)
                    }
                    .buttonStyle(.plain)

                    if index < ProfileSection.allCases.count - 1 {
                        Rectangle()
                            .fill(NADATheme.hairline.opacity(0.6))
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func sectionRow(_ section: ProfileSection) -> some View {
        let detail = completion.detail(for: section)
        let isComplete = completion.progress(for: section) >= 1

        return HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .frame(width: 24)

            Text(section.title)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.ink)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(isComplete ? NADATheme.secondaryInk : NADATheme.brand)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NADATheme.secondaryInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var missionCard: some View {
        VStack(spacing: 6) {
            Text("NADA is for real connections.")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            Text("We're building a safe, friendly space for people who just want to hang out.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)

            Image("SketchWelcomeHangout")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(NADATheme.brandSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var signOutButton: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 8) {
                Text("Log out")
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.brandPressed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .presentationDetents([.medium, .large])
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
            RemoteImageLoader.shared.prefetch(urlStrings: [avatarURL], targetPointSize: 132)
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
