import SwiftUI

/// Soft multi-step shell after basics: Photos → Bits → Discover card → Interests → Preferences.
/// Bits require 3 answers before Continue (W2-08); Preferences saves city radius (W2-10).
/// Job / university / hangout looking-for and interests are skippable and never block Discover.
struct ProfileSetupWizardView: View {
    @Environment(AuthManager.self) private var auth

    @State private var step: Step = .photos
    @State private var catalogBits: [Prompt] = []
    @State private var answers: [PromptAnswer] = []
    @State private var bitsLoadError: String?
    @State private var isLoadingBits = false
    @State private var selectedCategory: Prompt.Category?
    @State private var editorTarget: BitEditorTarget?
    @State private var radiusKm: Double = Double(ProfileLocation.defaultRadiusKm)
    @State private var city = ""
    @State private var lookingFor: UserPreferences.LookingForGender = .everyone
    @State private var minAge: Double = Double(UserPreferences.defaultMinAge)
    @State private var maxAge: Double = Double(UserPreferences.defaultMaxAge)
    @State private var approxLatitude: Double?
    @State private var approxLongitude: Double?
    @State private var localError: String?
    @State private var photoCount = 0
    @State private var photosNeedReplacement = false
    @State private var catalogInterests: [Interest] = []
    @State private var selectedInterestIds: [String] = []
    @State private var isLoadingInterests = false
    @State private var interestsLoadError: String?
    @State private var jobTitle = ""
    @State private var university = ""
    @State private var hangoutLookingFor = ""

    private let promptService = FirestorePromptService()
    private let interestService = FirestoreInterestService()

    private enum Step: Int, CaseIterable {
        case photos = 0
        case bits = 1
        case essentials = 2
        case interests = 3
        case preferences = 4

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .bits: return "Bits"
            case .essentials: return "Discover card"
            case .interests: return "Interests"
            case .preferences: return "Preferences"
            }
        }

        var headline: String {
            switch self {
            case .photos: return "Add your photos"
            case .bits: return "Answer 3 Bits"
            case .essentials: return "On your Discover card"
            case .interests: return "Add interest badges"
            case .preferences: return "Hangout preferences"
            }
        }

        var subtitle: String {
            switch self {
            case .photos:
                return "Add \(ProfilePhoto.maxCount) photos. Tap one to recrop it. The first is your main — drag to reorder."
            case .bits:
                return "Three short answers friends will see on your profile."
            case .essentials:
                return "Optional job, school, and hangout looking-for. Skip anything that doesn’t fit."
            case .interests:
                return "Up to \(InterestSelection.maxCount) badges on your Discover card. Skip if you’d rather add them later."
            case .preferences:
                return "Who you’d like to meet nearby. You can change this anytime."
            }
        }
    }

    private var hasRequiredPhotos: Bool {
        photoCount >= ProfilePhoto.maxCount && !photosNeedReplacement
    }

    private var answeredPromptIds: Set<String> {
        Set(answers.map(\.promptId))
    }

    private var canAddMoreBits: Bool {
        answers.count < PromptAnswer.maxCount
    }

    private var hasRequiredBits: Bool {
        answers.count >= PromptAnswer.maxCount
    }

    private var hasRequiredPreferences: Bool {
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableCategories: [Prompt.Category] {
        Prompt.Category.allCases.filter { category in
            catalogBits.contains { $0.category == category }
        }
    }

    private var filteredCatalog: [Prompt] {
        let base: [Prompt]
        if let selectedCategory {
            base = catalogBits.filter { $0.category == selectedCategory }
        } else {
            base = catalogBits
        }
        return base.filter { !answeredPromptIds.contains($0.id) }
    }

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: catalogBits.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: NADATheme.Layout.headerToContent) {
                        VStack(alignment: .leading, spacing: NADATheme.Layout.titleToSubtitle) {
                            Text(step.headline)
                                .font(NADATheme.displayFont)
                                .foregroundStyle(NADATheme.ink)
                            Text(step.subtitle)
                                .font(NADATheme.bodyFont)
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        stepContent

                        if let message = localError ?? auth.errorMessage {
                            NADAAuthErrorBanner(message: message)
                        }
                    }
                    .padding(.horizontal, NADATheme.Layout.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

                footer
            }
        }
        .task(id: step) {
            if step == .bits {
                await loadBitsStep()
            }
            if step == .essentials {
                hydrateEssentialsStep()
            }
            if step == .interests {
                await loadInterestsStep()
            }
            if step == .preferences {
                hydratePreferencesStep()
            }
        }
        .sheet(item: $editorTarget) { target in
            BitAnswerEditorSheet(
                catalog: catalogBits,
                answeredPromptIds: answeredPromptIds,
                initialPromptId: target.promptId,
                initialText: target.initialText,
                isEditing: target.isEditing
            ) { promptId, text in
                await saveBit(target: target, promptId: promptId, text: text)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            NADAOnboardingNavBar(
                showsSkip: step != .preferences,
                isBusy: auth.isBusy,
                onBack: goBack,
                onSkip: skipCurrentStep
            )

            Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? NADATheme.brand : NADATheme.brandSoft)
                        .frame(height: NADATheme.Layout.progressHeight)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .photos:
            photosStep
        case .bits:
            bitsStep
        case .essentials:
            essentialsStep
        case .interests:
            interestsStep
        case .preferences:
            preferencesStep
        }
    }

    private var photosStep: some View {
        ProfilePhotosEditor(
            showsHeaderCopy: false,
            onPhotosChanged: { photos in
                photoCount = photos.count
            },
            onReplacementRequiredChanged: { required in
                photosNeedReplacement = required
            }
        )
    }

    private var bitsStep: some View {
        BitsAnswersWorkspace(
            catalog: catalogBits,
            answers: $answers,
            selectedCategory: $selectedCategory,
            availableCategories: availableCategories,
            filteredCatalog: filteredCatalog,
            promptById: promptById,
            isLoading: isLoadingBits,
            errorMessage: bitsLoadError,
            canAddMore: canAddMoreBits,
            onSelectCatalog: { prompt in
                guard canAddMoreBits else { return }
                editorTarget = .compose(prompt)
            },
            onEditAnswer: { answer in
                editorTarget = .edit(answer, promptById[answer.promptId])
            },
            onDeleteAnswer: { answer in
                Task { await deleteBitAnswer(answer) }
            },
            onReorder: { orderedIds in
                Task { await persistBitOrder(orderedIds) }
            }
        )
    }

    private var essentialsStep: some View {
        ProfileHangoutEssentialsForm(
            jobTitle: $jobTitle,
            university: $university,
            hangoutLookingFor: $hangoutLookingFor,
            showsSectionHeader: false
        )
    }

    private var interestsStep: some View {
        ProfileInterestsEditor(
            catalog: catalogInterests,
            selectedIds: $selectedInterestIds,
            isLoading: isLoadingInterests,
            errorMessage: interestsLoadError,
            atLimitMessage: "That’s 8 — tap one to swap it out.",
            showsSelectionCount: false
        )
    }

    private var preferencesStep: some View {
        ProfilePreferencesForm(
            city: $city,
            radiusKm: $radiusKm,
            lookingFor: $lookingFor,
            minAge: $minAge,
            maxAge: $maxAge,
            approxLatitude: $approxLatitude,
            approxLongitude: $approxLongitude,
            detectionError: $localError,
            isBusy: auth.isBusy,
            autoDetectLocationOnAppear: true
        )
    }

    private func hydrateEssentialsStep() {
        localError = nil
        jobTitle = auth.currentUser?.trimmedJobTitle ?? ""
        university = auth.currentUser?.trimmedUniversity ?? ""
        hangoutLookingFor = auth.currentUser?.trimmedHangoutLookingFor ?? ""
    }

    private func saveEssentials() async -> Bool {
        localError = nil
        auth.clearError()
        guard let user = auth.currentUser,
              let gender = ProfileGender.fromStored(user.gender),
              let dateOfBirth = user.dateOfBirth else {
            localError = "Finish the basics first, then add these."
            return false
        }

        let ok = await auth.updateBasicProfile(
            displayName: user.displayName ?? "",
            gender: gender,
            city: user.city ?? "",
            dateOfBirth: dateOfBirth,
            jobTitle: jobTitle,
            university: university,
            hangoutLookingFor: hangoutLookingFor,
            updateHangoutEssentials: true
        )
        if !ok, auth.errorMessage == nil {
            localError = "Couldn't save your Discover card details. Try again."
        }
        return ok
    }

    private func hydratePreferencesStep() {
        localError = nil
        city = auth.currentPreferences?.trimmedCity
            ?? auth.currentUser?.city
            ?? ""
        radiusKm = Double(
            auth.currentPreferences?.resolvedRadiusKm
                ?? auth.currentUser?.resolvedRadiusKm
                ?? ProfileLocation.defaultRadiusKm
        )
        lookingFor = auth.currentPreferences?.lookingForGenders ?? .everyone
        minAge = Double(auth.currentPreferences?.minAge ?? UserPreferences.defaultMinAge)
        maxAge = Double(auth.currentPreferences?.maxAge ?? UserPreferences.defaultMaxAge)
        approxLatitude = auth.currentUser?.approxLatitude
        approxLongitude = auth.currentUser?.approxLongitude
    }

    private func loadInterestsStep() async {
        localError = nil
        interestsLoadError = nil
        if catalogInterests.isEmpty {
            selectedInterestIds = auth.currentUser?.interestIds ?? []
        }
        isLoadingInterests = true
        defer { isLoadingInterests = false }

        do {
            catalogInterests = try await interestService.fetchActiveInterests(locale: "en")
        } catch {
            interestsLoadError = "Couldn't load interests. Check Firestore rules and the `interests` seed."
        }
    }

    private func saveInterestIds() async -> Bool {
        localError = nil
        auth.clearError()
        let ok = await auth.updateInterestIds(selectedInterestIds)
        if !ok, auth.errorMessage == nil {
            localError = "Couldn't save your interests. Try again."
        }
        return ok
    }

    private var footer: some View {
        NADAStickyFooter {
            if step == .photos, !hasRequiredPhotos {
                Text(
                    photosNeedReplacement
                        ? "Add a photo to fill that spot"
                        : "Add \(ProfilePhoto.maxCount) photos to continue"
                )
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
            }

            if step == .bits, !hasRequiredBits {
                Text("Answer \(PromptAnswer.maxCount) Bits to continue")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            if step == .interests {
                Text("\(selectedInterestIds.count) / \(InterestSelection.maxCount) selected")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            if step == .essentials {
                Text("Optional — skip anything that doesn’t fit.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            if step == .preferences, !hasRequiredPreferences {
                Text("Add your city to finish setup")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            Button {
                Task { await advance() }
            } label: {
                if auth.isBusy {
                    ProgressView()
                        .tint(NADATheme.onBrand)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(step == .preferences ? "Finish" : "Continue")
                }
            }
            .nadaPrimaryCTA(enabled: canAdvance)
        }
    }

    private var canAdvance: Bool {
        !auth.isBusy
            && !(step == .photos && !hasRequiredPhotos)
            && !(step == .bits && !hasRequiredBits)
            && !(step == .preferences && !hasRequiredPreferences)
    }

    private func goBack() {
        localError = nil
        auth.clearError()
        if step == .photos {
            auth.isRevisitingBasicProfile = true
            return
        }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func skipCurrentStep() {
        localError = nil
        auth.clearError()
        guard step != .preferences, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func advance() async {
        localError = nil
        if step == .photos, !hasRequiredPhotos {
            localError = photosNeedReplacement
                ? "Add a photo to fill that spot."
                : "Add \(ProfilePhoto.maxCount) photos to continue."
            return
        }
        if step == .bits, !hasRequiredBits {
            localError = "Answer \(PromptAnswer.maxCount) Bits to continue."
            return
        }
        if step == .essentials {
            let saved = await saveEssentials()
            if !saved { return }
        }
        if step == .interests {
            let saved = await saveInterestIds()
            if !saved { return }
        }
        if step == .preferences {
            if !hasRequiredPreferences {
                localError = "City is required to finish setup."
                return
            }
            await finishWizard()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func finishWizard() async {
        guard let userId = auth.currentUser?.id else { return }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else {
            localError = "City is required."
            return
        }

        let age = UserPreferences.clampAgeRange(min: Int(minAge), max: Int(maxAge))
        var prefs = auth.currentPreferences ?? UserPreferences.defaults(
            for: auth.currentUser ?? NADAUser(id: userId)
        )
        prefs.city = trimmedCity
        prefs.radiusKm = ProfileLocation.clampRadiusKm(radiusKm)
        prefs.lookingForGenders = lookingFor
        prefs.minAge = age.min
        prefs.maxAge = age.max
        prefs.buddyTypes = [.openToAll]

        let prefsOK = await auth.updatePreferences(prefs)
        if !prefsOK {
            if auth.errorMessage == nil {
                localError = "Couldn't save your preferences. Try again."
            }
            return
        }

        if let approxLatitude, let approxLongitude {
            let locationOK = await auth.updateLocation(
                city: trimmedCity,
                radiusKm: prefs.resolvedRadiusKm,
                approxLatitude: approxLatitude,
                approxLongitude: approxLongitude
            )
            if !locationOK, auth.errorMessage == nil {
                localError = "Preferences saved, but approximate location couldn't be stored."
            }
        }

        let ok = await auth.completeProfileWizard()
        if !ok, auth.errorMessage == nil {
            localError = "Couldn't finish setup. Try again."
        }
    }

    private func loadBitsStep() async {
        isLoadingBits = true
        bitsLoadError = nil
        defer { isLoadingBits = false }

        do {
            async let catalogTask = promptService.fetchActivePrompts(locale: "en")
            answers = await auth.fetchBitAnswers()
            catalogBits = try await catalogTask
        } catch {
            bitsLoadError = "Couldn't load bits. Check Firestore rules and seed."
            catalogBits = []
        }
    }

    private func saveBit(target: BitEditorTarget, promptId: String, text: String) async -> Bool {
        localError = nil
        auth.clearError()

        switch target {
        case .compose:
            if let saved = await auth.saveBitAnswer(
                promptId: promptId,
                answerText: text,
                sortOrder: answers.count
            ) {
                answers.append(saved)
                answers.sort { $0.sortOrder < $1.sortOrder }
                return true
            }
        case .edit(let answer, _):
            if promptId == answer.promptId {
                if let saved = await auth.saveBitAnswer(
                    promptId: promptId,
                    answerText: text,
                    sortOrder: answer.sortOrder
                ) {
                    if let index = answers.firstIndex(where: { $0.promptId == saved.promptId }) {
                        answers[index] = saved
                    }
                    return true
                }
            } else if await auth.changeBitAnswerPrompt(
                fromPromptId: answer.promptId,
                toPromptId: promptId,
                answerText: text
            ) != nil {
                answers = await auth.fetchBitAnswers()
                return true
            }
        }

        localError = auth.errorMessage ?? "Couldn't save that Bit."
        return false
    }

    private func deleteBitAnswer(_ answer: PromptAnswer) async {
        localError = nil
        auth.clearError()
        if let updated = await auth.deleteBitAnswer(promptId: answer.promptId) {
            answers = updated
        } else {
            localError = auth.errorMessage ?? "Couldn't remove that Bit."
        }
    }

    private func persistBitOrder(_ orderedPromptIds: [String]) async {
        if let updated = await auth.reorderBitAnswers(orderedPromptIds: orderedPromptIds) {
            answers = updated
        } else {
            answers = await auth.fetchBitAnswers()
        }
    }
}

#Preview {
    ProfileSetupWizardView()
        .environment(AuthManager())
}
