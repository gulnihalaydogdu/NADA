import SwiftUI
import UniformTypeIdentifiers

/// Profile → Bits: pick a question, answer inline, then the next empty Bit appears.
struct ProfileBitsSheet: View {
    var initialBits: [Prompt] = []
    var onAnswersChanged: (() -> Void)? = nil

    @Environment(AuthManager.self) private var auth

    @State private var catalog: [Prompt] = []
    @State private var answers: [PromptAnswer] = []
    @State private var selectedCategory: Prompt.Category?
    @State private var composer = BitsComposer()
    @State private var isLoading = false
    @State private var localError: String?

    private let promptService = FirestorePromptService()

    private var availableCategories: [Prompt.Category] {
        Prompt.Category.allCases.filter { category in
            catalog.contains { $0.category == category }
        }
    }

    private var promptById: [String: Prompt] {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
    }

    var body: some View {
        ProfileSheetScaffold(title: composer.isPicking ? "Choose a Bit" : "Bits") {
            BitsAnswersWorkspace(
                catalog: catalog,
                composer: composer,
                selectedCategory: $selectedCategory,
                availableCategories: availableCategories,
                promptById: promptById,
                isLoading: isLoading,
                errorMessage: localError ?? auth.errorMessage,
                showsPickerBack: true,
                onSaveSlot: { slot, sortOrder in
                    await saveSlot(slot, sortOrder: sortOrder)
                },
                onDeleteAnswer: { answer in
                    await deleteAnswer(answer)
                },
                onChangePrompt: { fromPromptId, toPromptId, text in
                    await changePrompt(fromPromptId: fromPromptId, toPromptId: toPromptId, text: text)
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
            composer.hydrate(from: loadedAnswers)
        } catch {
            if catalog.isEmpty {
                localError = "Couldn't load bits. Check Firestore rules and the `prompts` seed."
            }
        }
    }

    private func saveSlot(_ slot: BitSlot, sortOrder: Int) async -> PromptAnswer? {
        guard let promptId = slot.promptId, slot.hasAnswer else { return slot.saved }
        localError = nil
        auth.clearError()

        if let saved = await auth.saveBitAnswer(
            promptId: promptId,
            answerText: slot.trimmedText,
            sortOrder: slot.saved?.sortOrder ?? sortOrder
        ) {
            if let index = answers.firstIndex(where: { $0.promptId == saved.promptId }) {
                answers[index] = saved
            } else {
                answers.append(saved)
                answers.sort { $0.sortOrder < $1.sortOrder }
            }
            onAnswersChanged?()
            return saved
        }

        localError = auth.errorMessage ?? "Couldn't save that Bit."
        return nil
    }

    private func changePrompt(fromPromptId: String, toPromptId: String, text: String) async -> PromptAnswer? {
        localError = nil
        auth.clearError()
        if let saved = await auth.changeBitAnswerPrompt(
            fromPromptId: fromPromptId,
            toPromptId: toPromptId,
            answerText: text
        ) {
            answers = await auth.fetchBitAnswers()
            onAnswersChanged?()
            return saved
        }
        localError = auth.errorMessage ?? "Couldn't change that Bit."
        return nil
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

// MARK: - Slot model

struct BitSlot: Identifiable, Equatable {
    let id: UUID
    var promptId: String?
    var text: String
    var saved: PromptAnswer?

    static func empty() -> BitSlot {
        BitSlot(id: UUID(), promptId: nil, text: "", saved: nil)
    }

    static func from(_ answer: PromptAnswer) -> BitSlot {
        BitSlot(id: UUID(), promptId: answer.promptId, text: answer.answerText, saved: answer)
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasPrompt: Bool { promptId != nil }
    var hasAnswer: Bool { promptId != nil && !trimmedText.isEmpty }
}

@MainActor
@Observable
final class BitsComposer {
    var slots: [BitSlot] = []
    var pickingSlotID: UUID?
    var pendingFocusSlotID: UUID?

    var isPicking: Bool { pickingSlotID != nil }

    var answeredCount: Int { slots.filter(\.hasAnswer).count }

    var chosenPromptCount: Int { slots.filter(\.hasPrompt).count }

    var pickingSlot: BitSlot? {
        guard let pickingSlotID else { return nil }
        return slots.first { $0.id == pickingSlotID }
    }

    var emptyPickLabel: String {
        switch chosenPromptCount {
        case 0: return "Add your first Bit"
        case 1: return "Add your second Bit"
        default: return "Add your third Bit"
        }
    }

    func hydrate(from answers: [PromptAnswer]) {
        let drafts = slots.filter { $0.hasPrompt && $0.saved == nil }
        slots = answers.map(BitSlot.from)
        for draft in drafts where !slots.contains(where: { $0.promptId == draft.promptId }) {
            guard chosenPromptCount < PromptAnswer.maxCount else { break }
            slots.append(draft)
        }
        ensureTrailingEmpty()
    }

    func ensureTrailingEmpty() {
        slots.removeAll { !$0.hasPrompt }
        if chosenPromptCount < PromptAnswer.maxCount {
            slots.append(.empty())
        }
    }

    func beginPicking(_ slot: BitSlot) {
        pickingSlotID = slot.id
        pendingFocusSlotID = nil
    }

    func cancelPicking() {
        pickingSlotID = nil
    }

    func applyPrompt(_ prompt: Prompt) {
        guard let pickingSlotID,
              let index = slots.firstIndex(where: { $0.id == pickingSlotID }) else { return }
        if slots[index].promptId != prompt.id {
            slots[index].promptId = prompt.id
        }
        self.pickingSlotID = nil
        pendingFocusSlotID = slots[index].id
        ensureTrailingEmpty()
    }

    func restoreAnswersIfSlotIDsDropped() {
        for index in slots.indices {
            guard BitSlotDrag.isSlotID(slots[index].text, in: slots) else { continue }
            slots[index].text = slots[index].saved?.answerText ?? ""
        }
    }

    func removeSlot(_ slot: BitSlot) {
        slots.removeAll { $0.id == slot.id }
        if pickingSlotID == slot.id {
            pickingSlotID = nil
        }
        ensureTrailingEmpty()
    }
}

// MARK: - Shared workspace (sheet + wizard)

struct BitsAnswersWorkspace: View {
    let catalog: [Prompt]
    var composer: BitsComposer
    @Binding var selectedCategory: Prompt.Category?
    let availableCategories: [Prompt.Category]
    let promptById: [String: Prompt]
    let isLoading: Bool
    let errorMessage: String?
    var showsPickerBack = false
    var onSaveSlot: (BitSlot, Int) async -> PromptAnswer?
    var onDeleteAnswer: (PromptAnswer) async -> Void
    var onChangePrompt: (_ fromPromptId: String, _ toPromptId: String, _ text: String) async -> PromptAnswer?
    var onReorder: ([String]) -> Void

    @FocusState private var focusedSlotID: UUID?
    @State private var draggingSlotID: UUID?

    private var occupiedPromptIds: Set<String> {
        let current = composer.pickingSlot?.promptId
        return Set(composer.slots.compactMap(\.promptId).filter { $0 != current })
    }

    private var filteredCatalog: [Prompt] {
        let base: [Prompt]
        if let selectedCategory {
            base = catalog.filter { $0.category == selectedCategory }
        } else {
            base = catalog
        }
        return base.filter { !occupiedPromptIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if composer.isPicking {
                pickerContent
            } else {
                slotsContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedSlotID = nil
                }
                .font(NADATheme.bodyFont.weight(.semibold))
                .foregroundStyle(NADATheme.brandPressed)
            }
        }
        .onChange(of: composer.pendingFocusSlotID) { _, newValue in
            guard let newValue else { return }
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                focusedSlotID = newValue
                composer.pendingFocusSlotID = nil
            }
        }
        .onChange(of: focusedSlotID) { oldValue, newValue in
            guard let oldValue, oldValue != newValue else { return }
            Task { await persistSlot(id: oldValue) }
        }
        .onAppear {
            composer.restoreAnswersIfSlotIDsDropped()
        }
    }

    private var slotsContent: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if composer.chosenPromptCount >= 2 {
                Text("Drag Bits to reorder")
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .nadaDismissKeyboardOnTap()
            }

            if isLoading && catalog.isEmpty && composer.chosenPromptCount == 0 {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let errorMessage, catalog.isEmpty && composer.chosenPromptCount == 0 {
                Text(errorMessage)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
            } else if catalog.isEmpty && composer.chosenPromptCount == 0 {
                Text("No bits in the catalog yet. Seed the `prompts` collection in Firestore.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            } else {
                ForEach(composer.slots) { slot in
                    if slot.hasPrompt {
                        composingCard(slot)
                    } else {
                        BitEmptyPickCard(title: composer.emptyPickLabel) {
                            focusedSlotID = nil
                            composer.beginPicking(slot)
                        }
                    }
                }

                if composer.chosenPromptCount > 0 {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .nadaDismissKeyboardOnTap()
                }

                if let errorMessage, !(catalog.isEmpty && composer.chosenPromptCount == 0) {
                    Text(errorMessage)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                }
            }
        }
    }

    private var pickerContent: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if showsPickerBack {
                Button {
                    composer.cancelPicking()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(NADATheme.bodyFont.weight(.semibold))
                    }
                    .foregroundStyle(NADATheme.brandPressed)
                }
                .buttonStyle(.plain)
            }

            BitCatalogPickerList(
                prompts: filteredCatalog,
                availableCategories: availableCategories,
                selectedCategory: $selectedCategory,
                selectedId: composer.pickingSlot?.promptId
            ) { prompt in
                composer.applyPrompt(prompt)
            }
        }
    }

    private func composingCard(_ slot: BitSlot) -> some View {
        let isDragging = draggingSlotID == slot.id
        let promptText = promptById[slot.promptId ?? ""]?.text ?? "Bit"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if composer.chosenPromptCount >= 2 {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NADATheme.secondaryInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onDrag {
                            draggingSlotID = slot.id
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(
                                forTypeIdentifier: BitSlotDrag.utType.identifier,
                                visibility: .ownProcess
                            ) { completion in
                                completion(slot.id.uuidString.data(using: .utf8), nil)
                                return nil
                            }
                            return provider
                        }
                        .accessibilityLabel("Reorder Bit")
                }

                Button {
                    focusedSlotID = nil
                    composer.beginPicking(slot)
                } label: {
                    Text(promptText)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.brandPressed)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change Bit question")

                Button {
                    Task { await deleteSlot(slot) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Bit")
            }

            TextField("Add a short answer", text: textBinding(for: slot), axis: .vertical)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.ink)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .focused($focusedSlotID, equals: slot.id)
                .submitLabel(.done)
                .onSubmit {
                    focusedSlotID = nil
                }

            Text("\(min(slot.trimmedText.count, PromptAnswer.maxTextLength))/\(PromptAnswer.maxTextLength)")
                .font(NADATheme.captionFont)
                .foregroundStyle(
                    slot.trimmedText.count > PromptAnswer.maxTextLength
                        ? NADATheme.danger
                        : NADATheme.secondaryInk
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NADATheme.ink.opacity(0.06), lineWidth: 1)
        )
        .opacity(isDragging ? 0.55 : 1)
        .onDrop(
            of: [BitSlotDrag.utType],
            delegate: BitSlotReorderDropDelegate(
                targetId: slot.id,
                composer: composer,
                draggingSlotID: $draggingSlotID,
                onFinished: {
                    persistPromptedOrder()
                }
            )
        )
    }

    private func textBinding(for slot: BitSlot) -> Binding<String> {
        Binding(
            get: {
                composer.slots.first(where: { $0.id == slot.id })?.text ?? slot.text
            },
            set: { updateText($0, for: slot) }
        )
    }

    private func updateText(_ newValue: String, for slot: BitSlot) {
        guard let index = composer.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        // Drag used to advertise the slot UUID as public.text, which TextField
        // treated as a drop and pasted over the answer.
        if BitSlotDrag.isSlotID(newValue, in: composer.slots) { return }
        composer.slots[index].text = String(newValue.prefix(PromptAnswer.maxTextLength))
    }

    private func persistSlot(id: UUID) async {
        guard let index = composer.slots.firstIndex(where: { $0.id == id }) else { return }
        let slot = composer.slots[index]
        guard let promptId = slot.promptId, slot.hasAnswer else { return }
        if BitSlotDrag.isSlotID(slot.trimmedText, in: composer.slots) { return }

        if let saved = slot.saved,
           saved.promptId == promptId,
           saved.answerText == slot.trimmedText {
            return
        }

        let sortOrder = composer.slots.filter(\.hasPrompt).firstIndex(where: { $0.id == id }) ?? index

        if let saved = slot.saved, saved.promptId != promptId {
            if let updated = await onChangePrompt(saved.promptId, promptId, slot.trimmedText) {
                composer.slots[index].saved = updated
                composer.slots[index].text = updated.answerText
            }
            return
        }

        if let saved = await onSaveSlot(slot, sortOrder) {
            composer.slots[index].saved = saved
            composer.slots[index].text = saved.answerText
        }
    }

    private func deleteSlot(_ slot: BitSlot) async {
        focusedSlotID = nil
        if let saved = slot.saved {
            await onDeleteAnswer(saved)
        }
        composer.removeSlot(slot)
    }

    private func persistPromptedOrder() {
        let savedIds = composer.slots.compactMap(\.saved?.promptId)
        let promptedIds = composer.slots.compactMap(\.promptId)
        guard savedIds.count == promptedIds.count,
              Set(savedIds) == Set(promptedIds) else { return }
        onReorder(promptedIds)
    }
}

private struct BitEmptyPickCard: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NADATheme.bodyFont.weight(.medium))
                .foregroundStyle(NADATheme.brandPressed)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 148)
                .background(
                    NADATheme.brandSoft.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            NADATheme.brand.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens the Bit question list")
    }
}

private enum BitSlotDrag {
    /// In-process reorder payload. `UTType.data` so the answer TextField
    /// does not treat the drop as pasted text (and no custom UTI in Info.plist).
    static let utType = UTType.data

    static func isSlotID(_ text: String, in slots: [BitSlot]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return false }
        return slots.contains { $0.id.uuidString.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

// MARK: - Drag & drop

struct BitSlotReorderDropDelegate: DropDelegate {
    let targetId: UUID
    var composer: BitsComposer
    @Binding var draggingSlotID: UUID?
    var onFinished: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingSlotID,
              draggingSlotID != targetId,
              let from = composer.slots.firstIndex(where: { $0.id == draggingSlotID }),
              let to = composer.slots.firstIndex(where: { $0.id == targetId }),
              composer.slots[from].hasPrompt,
              composer.slots[to].hasPrompt,
              from != to else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            composer.slots.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSlotID = nil
        composer.restoreAnswersIfSlotIDsDropped()
        onFinished()
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - Catalog picker (full-screen content, not a sheet)

struct BitCatalogPickerList: View {
    let prompts: [Prompt]
    let availableCategories: [Prompt.Category]
    @Binding var selectedCategory: Prompt.Category?
    var selectedId: String?
    var onSelect: (Prompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            categoryChips

            if prompts.isEmpty {
                Text("No more Bits in this category — try All or another chip.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            } else {
                ForEach(prompts) { prompt in
                    catalogCard(prompt)
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
