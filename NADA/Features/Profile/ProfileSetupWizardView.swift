import SwiftUI

/// Soft multi-step shell after basics: Photos → Bits → Preferences.
/// Bits require 3 answers before Continue (W2-08); Preferences saves city radius (W2-10).
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
    @State private var localError: String?
    @State private var photoCount = 0
    @State private var photosNeedReplacement = false

    private let promptService = FirestorePromptService()

    private enum Step: Int, CaseIterable {
        case photos = 0
        case bits = 1
        case preferences = 2

        var title: String {
            switch self {
            case .photos: return "Photos"
            case .bits: return "Bits"
            case .preferences: return "Preferences"
            }
        }

        var headline: String {
            switch self {
            case .photos: return "Add your photos"
            case .bits: return "Answer 3 Bits"
            case .preferences: return "Hangout preferences"
            }
        }

        var subtitle: String {
            switch self {
            case .photos:
                return "Add \(ProfilePhoto.maxCount) photos. The first one is your main profile photo — drag to reorder, or tap ✕ to swap one out."
            case .bits:
                return "Pick three questions and write short answers friends will see on your profile."
            case .preferences:
                return "Confirm how far Discover should look. Interests come later — you can edit radius anytime in Profile."
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
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(step.headline)
                                .font(NADATheme.displayFont)
                                .foregroundStyle(NADATheme.ink)
                            Text(step.subtitle)
                                .font(NADATheme.bodyFont)
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        stepContent

                        if let message = localError ?? auth.errorMessage {
                            Text(message)
                                .font(NADATheme.captionFont)
                                .foregroundStyle(NADATheme.danger)
                        }
                    }
                    .padding(24)
                }

                footer
            }
        }
        .task(id: step) {
            if step == .bits {
                await loadBitsStep()
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
            HStack {
                if step != .photos {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NADATheme.ink)
                            .frame(width: 36, height: 36)
                            .background(NADATheme.surface, in: Circle())
                    }
                    .accessibilityLabel("Back")
                }

                Spacer()

                Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? NADATheme.brand : NADATheme.brandSoft)
                        .frame(height: 4)
                }
            }

            Text(step.title)
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.brandPressed)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .photos:
            photosStep
        case .bits:
            bitsStep
        case .preferences:
            preferencesStep
        }
    }

    private var photosStep: some View {
        ProfilePhotosEditor(
            showsHeaderCopy: true,
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

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("City")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                Text(auth.currentUser?.city?.isEmpty == false ? (auth.currentUser?.city ?? "") : "Not set")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Discover radius")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                    Spacer()
                    Text("\(Int(radiusKm)) km")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.warmSecondaryInk)
                }
                Slider(
                    value: $radiusKm,
                    in: Double(ProfileLocation.minimumRadiusKm)...Double(ProfileLocation.maximumRadiusKm),
                    step: Double(ProfileLocation.radiusStepKm)
                )
                .tint(NADATheme.brand)
                Text("Saved when you tap Finish. Friends never see a precise pin.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Interests")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
                Text("Coffee · Walks · Games · Music · Food")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                Text("Interest picks come later.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            radiusKm = Double(
                auth.currentPreferences?.resolvedRadiusKm
                    ?? auth.currentUser?.resolvedRadiusKm
                    ?? ProfileLocation.defaultRadiusKm
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
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

            Button {
                Task { await advance() }
            } label: {
                if auth.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(step == .preferences ? "Finish" : "Continue")
                }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .disabled(
                auth.isBusy
                    || (step == .photos && !hasRequiredPhotos)
                    || (step == .bits && !hasRequiredBits)
            )

            if step == .preferences {
                Button {
                    Task { await skipOrFinish() }
                } label: {
                    Text("Skip for now")
                        .font(NADATheme.headlineFont)
                        .foregroundStyle(NADATheme.brandPressed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .disabled(auth.isBusy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 28, topTrailing: 28),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func goBack() {
        localError = nil
        auth.clearError()
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
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
        if step == .preferences {
            await finishWizard()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func skipOrFinish() async {
        localError = nil
        auth.clearError()
        if step == .preferences {
            await finishWizard(saveRadius: false)
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func finishWizard(saveRadius: Bool = true) async {
        if saveRadius,
           let city = auth.currentUser?.city?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty {
            let locationOK = await auth.updateLocation(
                city: city,
                radiusKm: ProfileLocation.clampRadiusKm(radiusKm)
            )
            if !locationOK {
                if auth.errorMessage == nil {
                    localError = "Couldn't save your radius. Try again."
                }
                return
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
