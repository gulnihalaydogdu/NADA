import SwiftUI
import UniformTypeIdentifiers

/// Profile → Bits: answer up to 3 catalog prompts; drag reorder, ✕ delete, edit prompt + answer.
struct ProfileBitsSheet: View {
    var initialBits: [Prompt] = []
    var onAnswersChanged: (() -> Void)? = nil

    @Environment(AuthManager.self) private var auth

    @State private var catalog: [Prompt] = []
    @State private var answers: [PromptAnswer] = []
    @State private var selectedCategory: Prompt.Category?
    @State private var isLoading = false
    @State private var localError: String?
    @State private var editorTarget: BitEditorTarget?

    private let promptService = FirestorePromptService()

    private var answeredPromptIds: Set<String> {
        Set(answers.map(\.promptId))
    }

    private var canAddMore: Bool {
        answers.count < PromptAnswer.maxCount
    }

    private var availableCategories: [Prompt.Category] {
        Prompt.Category.allCases.filter { category in
            catalog.contains { $0.category == category }
        }
    }

    private var filteredCatalog: [Prompt] {
        let base: [Prompt]
        if let selectedCategory {
            base = catalog.filter { $0.category == selectedCategory }
        } else {
            base = catalog
        }
        return base.filter { !answeredPromptIds.contains($0.id) }
    }

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    }

    var body: some View {
        ProfileSheetScaffold(title: "Bits") {
            BitsAnswersWorkspace(
                catalog: catalog,
                answers: $answers,
                selectedCategory: $selectedCategory,
                availableCategories: availableCategories,
                filteredCatalog: filteredCatalog,
                promptById: promptById,
                isLoading: isLoading,
                errorMessage: localError ?? auth.errorMessage,
                canAddMore: canAddMore,
                onSelectCatalog: { prompt in
                    guard canAddMore else { return }
                    editorTarget = .compose(prompt)
                },
                onEditAnswer: { answer in
                    editorTarget = .edit(answer, promptById[answer.promptId])
                },
                onDeleteAnswer: { answer in
                    Task { await deleteAnswer(answer) }
                },
                onReorder: { orderedIds in
                    Task { await persistOrder(orderedIds) }
                }
            )
        }
        .task {
            if catalog.isEmpty { catalog = initialBits }
            await reload()
        }
        .sheet(item: $editorTarget) { target in
            BitAnswerEditorSheet(
                catalog: catalog,
                answeredPromptIds: answeredPromptIds,
                initialPromptId: target.promptId,
                initialText: target.initialText,
                isEditing: target.isEditing
            ) { promptId, text in
                await save(target: target, promptId: promptId, text: text)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func reload() async {
        isLoading = true
        localError = nil
        defer { isLoading = false }

        do {
            async let catalogTask = promptService.fetchActivePrompts(locale: "en")
            let loadedAnswers = await auth.fetchBitAnswers()
            catalog = try await catalogTask
            answers = loadedAnswers
        } catch {
            if catalog.isEmpty {
                localError = "Couldn't load bits. Check Firestore rules and the `prompts` seed."
            }
        }
    }

    private func save(target: BitEditorTarget, promptId: String, text: String) async -> Bool {
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
                onAnswersChanged?()
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
                    onAnswersChanged?()
                    return true
                }
            } else if await auth.changeBitAnswerPrompt(
                fromPromptId: answer.promptId,
                toPromptId: promptId,
                answerText: text
            ) != nil {
                answers = await auth.fetchBitAnswers()
                onAnswersChanged?()
                return true
            }
        }

        localError = auth.errorMessage ?? "Couldn't save that Bit."
        return false
    }

    private func deleteAnswer(_ answer: PromptAnswer) async {
        localError = nil
        auth.clearError()
        if let updated = await auth.deleteBitAnswer(promptId: answer.promptId) {
            answers = updated
            onAnswersChanged?()
        } else {
            localError = auth.errorMessage ?? "Couldn't remove that Bit."
        }
    }

    private func persistOrder(_ orderedPromptIds: [String]) async {
        if let updated = await auth.reorderBitAnswers(orderedPromptIds: orderedPromptIds) {
            answers = updated
            onAnswersChanged?()
        } else {
            answers = await auth.fetchBitAnswers()
        }
    }
}

// MARK: - Shared workspace (sheet + wizard)

struct BitsAnswersWorkspace: View {
    let catalog: [Prompt]
    @Binding var answers: [PromptAnswer]
    @Binding var selectedCategory: Prompt.Category?
    let availableCategories: [Prompt.Category]
    let filteredCatalog: [Prompt]
    let promptById: [String: Prompt]
    let isLoading: Bool
    let errorMessage: String?
    let canAddMore: Bool
    var onSelectCatalog: (Prompt) -> Void
    var onEditAnswer: (PromptAnswer) -> Void
    var onDeleteAnswer: (PromptAnswer) -> Void
    var onReorder: ([String]) -> Void

    @State private var draggingAnswerId: String?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text("\(answers.count) of \(PromptAnswer.maxCount) answered")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            Text("Drag Bits to reorder. Tap ✕ to remove one, or tap a card to edit the question and answer.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)

            if isLoading && catalog.isEmpty && answers.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let errorMessage, catalog.isEmpty && answers.isEmpty {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            } else if catalog.isEmpty && answers.isEmpty {
                Text("No bits in the catalog yet. Seed the `prompts` collection in Firestore.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            } else {
                if !answers.isEmpty {
                    sectionTitle("Your answers")
                    ForEach(answers) { answer in
                        answeredCard(answer)
                    }
                }

                if canAddMore {
                    sectionTitle(answers.isEmpty ? "Choose a Bit" : "Add another")
                    categoryChips
                    if filteredCatalog.isEmpty {
                        Text("No more Bits in this category — try All or another chip.")
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                    } else {
                        ForEach(filteredCatalog) { bit in
                            catalogCard(bit)
                        }
                    }
                } else {
                    Text("You've answered \(PromptAnswer.maxCount) Bits. Edit one, or remove one with ✕ to pick a different question.")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }

                if let errorMessage, !(catalog.isEmpty && answers.isEmpty) {
                    Text(errorMessage)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.ink)
            .padding(.top, 4)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(availableCategories) { category in
                    chip(title: category.title, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(NADATheme.captionFont)
            }
            .foregroundStyle(isSelected ? NADATheme.onBrand : NADATheme.warmSecondaryInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? NADATheme.brand : NADATheme.card, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : NADATheme.ink.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private func answeredCard(_ answer: PromptAnswer) -> some View {
        let isDragging = draggingAnswerId == answer.id

        return Button {
            onEditAnswer(answer)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(promptById[answer.promptId]?.text ?? "Bit")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)
                    .padding(.trailing, 28)
                Text(answer.answerText)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.ink)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                onDeleteAnswer(answer)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Remove Bit")
        }
        .opacity(isDragging ? 0.55 : 1)
        .onDrag {
            draggingAnswerId = answer.id
            return NSItemProvider(object: answer.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: BitReorderDropDelegate(
                targetId: answer.id,
                answers: $answers,
                draggingAnswerId: $draggingAnswerId,
                onFinished: { ids in
                    onReorder(ids)
                }
            )
        )
        .accessibilityHint("Drag to reorder")
    }

    private func catalogCard(_ bit: Prompt) -> some View {
        Button {
            onSelectCatalog(bit)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(bit.text)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.ink)
                    .multilineTextAlignment(.leading)
                Text(bit.category.title)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.brandPressed)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAddMore)
    }
}

// MARK: - Drag & drop

struct BitReorderDropDelegate: DropDelegate {
    let targetId: String
    @Binding var answers: [PromptAnswer]
    @Binding var draggingAnswerId: String?
    var onFinished: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingAnswerId,
              draggingAnswerId != targetId,
              let from = answers.firstIndex(where: { $0.id == draggingAnswerId }),
              let to = answers.firstIndex(where: { $0.id == targetId }),
              from != to else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            answers.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            for index in answers.indices {
                answers[index].sortOrder = index
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingAnswerId = nil
        onFinished(answers.map(\.promptId))
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - Editor target

enum BitEditorTarget: Identifiable {
    case compose(Prompt)
    case edit(PromptAnswer, Prompt?)

    var id: String {
        switch self {
        case .compose(let prompt): return "new-\(prompt.id)"
        case .edit(let answer, _): return "edit-\(answer.id)"
        }
    }

    var promptId: String {
        switch self {
        case .compose(let prompt): return prompt.id
        case .edit(let answer, _): return answer.promptId
        }
    }

    var initialText: String {
        switch self {
        case .compose: return ""
        case .edit(let answer, _): return answer.answerText
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

// MARK: - Editor (Hinge-style prompt + answer)

struct BitAnswerEditorSheet: View {
    let catalog: [Prompt]
    let answeredPromptIds: Set<String>
    let initialPromptId: String
    let initialText: String
    let isEditing: Bool
    var onSave: (_ promptId: String, _ text: String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPromptId: String = ""
    @State private var text: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPromptPicker = false

    private var selectedPrompt: Prompt? {
        catalog.first { $0.id == selectedPromptId }
    }

    private var selectablePrompts: [Prompt] {
        catalog.filter { prompt in
            prompt.id == initialPromptId || !answeredPromptIds.contains(prompt.id)
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        selectedPrompt != nil
            && !trimmed.isEmpty
            && trimmed.count <= PromptAnswer.maxTextLength
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Prompt row with pencil (Hinge-style)
                HStack(spacing: 0) {
                    Text(selectedPrompt?.text ?? "Choose a Bit")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)

                    Rectangle()
                        .fill(NADATheme.ink.opacity(0.1))
                        .frame(width: 1, height: 28)

                    Button {
                        showPromptPicker = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NADATheme.brandPressed)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change Bit question")
                }
                .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1)
                )

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1)
                        )

                    if text.isEmpty {
                        Text("Your answer")
                            .font(NADATheme.bodyFont)
                            .foregroundStyle(NADATheme.secondaryInk.opacity(0.7))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(trimmed.count)")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(
                            trimmed.count > PromptAnswer.maxTextLength
                                ? NADATheme.danger
                                : NADATheme.secondaryInk
                        )
                        .padding(12)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }

                Spacer()
            }
            .padding(24)
            .background(NADATheme.paper.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Bit" : "Answer Bit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NADATheme.brandPressed)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                selectedPromptId = initialPromptId
                text = initialText
            }
            .sheet(isPresented: $showPromptPicker) {
                BitCatalogPickerSheet(
                    prompts: selectablePrompts,
                    selectedId: selectedPromptId
                ) { prompt in
                    selectedPromptId = prompt.id
                    showPromptPicker = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func save() async {
        guard let selectedPromptId = selectedPrompt?.id else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let ok = await onSave(selectedPromptId, trimmed)
        if ok {
            dismiss()
        } else {
            errorMessage = "Couldn't save. Try again."
        }
    }
}

/// Same category-chip catalog UI used when first picking a Bit.
struct BitCatalogPickerSheet: View {
    let prompts: [Prompt]
    let selectedId: String
    var onSelect: (Prompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Prompt.Category?

    private var availableCategories: [Prompt.Category] {
        Prompt.Category.allCases.filter { category in
            prompts.contains { $0.category == category }
        }
    }

    private var filtered: [Prompt] {
        guard let selectedCategory else { return prompts }
        return prompts.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Pick a Bit question")
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.warmSecondaryInk)

                    categoryChips

                    if filtered.isEmpty {
                        Text("No Bits in this category — try All.")
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                    } else {
                        ForEach(filtered) { prompt in
                            catalogCard(prompt)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(NADATheme.paper.ignoresSafeArea())
            .navigationTitle("Choose a Bit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(availableCategories) { category in
                    chip(title: category.title, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(NADATheme.captionFont)
            }
            .foregroundStyle(isSelected ? NADATheme.onBrand : NADATheme.warmSecondaryInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? NADATheme.brand : NADATheme.card, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : NADATheme.ink.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private func catalogCard(_ prompt: Prompt) -> some View {
        let isSelected = prompt.id == selectedId
        return Button {
            onSelect(prompt)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.text)
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(prompt.category.title)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.brandPressed)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NADATheme.brand)
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? NADATheme.brand.opacity(0.55) : NADATheme.ink.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileBitsSheet()
        .environment(AuthManager())
}
