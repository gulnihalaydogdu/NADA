import SwiftUI

/// One-at-a-time Discover feed (W3-06) — loads candidates from W3-01.
struct DiscoverFeedView: View {
    @Environment(AuthManager.self) private var auth

    @State private var queue: [DiscoverCandidate] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isActing = false
    @State private var hasLoadedOnce = false
    @State private var localError: String?
    @State private var scrollToTopToken = 0
    /// Last skipped card kept in memory so Undo can restore without a full refetch.
    @State private var lastSkipped: DiscoverCandidate?
    @State private var likeDraft: LikeDraft?

    private var current: DiscoverCandidate? { queue.first }

    private struct LikeDraft: Identifiable {
        let id = UUID()
        let toUserId: String
        let targetType: DiscoverLike.TargetType
        let targetId: String
        let title: String
    }

    var body: some View {
        ZStack {
            NADAScreenBackground()

            if !auth.isProfileComplete {
                incompleteGate
            } else {
                feedContent
            }
        }
        .task(id: auth.currentUser?.id) {
            guard auth.isProfileComplete else { return }
            await reload()
        }
    }

    // MARK: - States

    private var incompleteGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(20)
                .background(NADATheme.brandSoft, in: Circle())

            Text("Finish your profile")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)

            Text("Add photos, Bits, and basics so you can discover people nearby.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Text("Open the Profile tab to continue.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
        }
        .padding(24)
    }

    @ViewBuilder
    private var feedContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if let message = localError ?? auth.errorMessage {
                Text(message)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            if isLoading && queue.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let current {
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id("discoverTop")

                        DiscoverCandidateStack(
                            candidate: current,
                            onLikeBit: { bit in
                                likeDraft = LikeDraft(
                                    toUserId: current.id,
                                    targetType: .prompt,
                                    targetId: bit.id,
                                    title: bit.promptText
                                )
                            }
                        )
                            .id(current.id)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                    .onChange(of: scrollToTopToken) { _, _ in
                        proxy.scrollTo("discoverTop", anchor: .top)
                    }
                    .onChange(of: current.id) { _, _ in
                        proxy.scrollTo("discoverTop", anchor: .top)
                    }
                }

                actionBar
            } else if hasLoadedOnce {
                emptyState
            } else {
                Spacer()
            }
        }
        .sheet(item: $likeDraft) { draft in
            DiscoverLikeCommentSheet(
                title: draft.title,
                isBusy: isActing
            ) { comment in
                Task {
                    await sendLike(
                        toUserId: draft.toUserId,
                        targetType: draft.targetType,
                        targetId: draft.targetId,
                        comment: comment
                    )
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Text("Discover")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
            Spacer()
            if let distance = current?.distanceKm {
                Text(distanceLabel(distance))
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(20)
                .background(NADATheme.brandSoft, in: Circle())

            Text("No one nearby yet")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)

            Text("Try widening your Discover radius or check back later — hangout buddies will show up here.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                Task { await reload() }
            } label: {
                Text("Refresh")
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .padding(.horizontal, 48)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    Task { await undoSkip() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(lastSkipped == nil || isActing ? NADATheme.secondaryInk : NADATheme.ink)
                        .frame(width: 56, height: 56)
                        .background(NADATheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1))
                }
                .disabled(lastSkipped == nil || isActing || isLoading)
                .accessibilityLabel("Undo skip")

                Button {
                    Task { await skipCurrent() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NADATheme.ink)
                        .frame(width: 64, height: 64)
                        .background(NADATheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1))
                }
                .disabled(current == nil || isActing || isLoading)
                .accessibilityLabel("Skip")

                Button {
                    guard let current else { return }
                    likeDraft = LikeDraft(
                        toUserId: current.id,
                        targetType: .profile,
                        targetId: current.id,
                        title: current.displayName
                    )
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(NADATheme.onBrand)
                        .frame(width: 64, height: 64)
                        .background(NADATheme.brand, in: Circle())
                }
                .disabled(current == nil || isActing || isLoading)
                .accessibilityLabel("Like profile")
            }

            Text("Like a Bit on the card, or the whole profile. Skip to pass — Undo brings them back.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 24, topTrailing: 24),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Actions

    private func reload() async {
        localError = nil
        auth.clearError()
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        guard let page = await auth.fetchDiscoverPage(cursor: nil) else {
            if auth.errorMessage == nil {
                localError = "Couldn't load Discover. Try again."
            }
            queue = []
            cursor = nil
            return
        }

        queue = page.candidates
        cursor = page.cursor
        prefetchUpcomingPhotos()
        scrollToTopToken += 1
    }

    private func removeCurrentFromQueue() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        scrollToTopToken += 1
        prefetchUpcomingPhotos()
        if queue.count <= 2 {
            Task { await loadMoreIfNeeded() }
        }
    }

    private func skipCurrent() async {
        guard let current, !isActing else { return }
        isActing = true
        localError = nil
        defer { isActing = false }

        if await auth.skipDiscoverUser(current.id) != nil {
            lastSkipped = current
            removeCurrentFromQueue()
        } else if auth.errorMessage == nil {
            localError = "Couldn't skip. Try again."
        }
    }

    private func sendLike(
        toUserId: String,
        targetType: DiscoverLike.TargetType,
        targetId: String,
        comment: String?
    ) async {
        guard !isActing else { return }
        isActing = true
        localError = nil
        defer { isActing = false }

        if await auth.likeDiscoverTarget(
            toUserId: toUserId,
            targetType: targetType,
            targetId: targetId,
            comment: comment
        ) != nil {
            likeDraft = nil
            if queue.first?.id == toUserId {
                if lastSkipped?.id == toUserId { lastSkipped = nil }
                removeCurrentFromQueue()
            }
        } else if auth.errorMessage == nil {
            localError = "Couldn't send that like."
        }
    }

    private func undoSkip() async {
        guard let restored = lastSkipped, !isActing else { return }
        isActing = true
        localError = nil
        defer { isActing = false }

        if await auth.undoDiscoverSkip(toUserId: restored.id) {
            queue.removeAll { $0.id == restored.id }
            queue.insert(restored, at: 0)
            lastSkipped = nil
            scrollToTopToken += 1
        } else if auth.errorMessage == nil {
            localError = "Nothing to undo."
        }
    }

    private func loadMoreIfNeeded() async {
        guard let cursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let page = await auth.fetchDiscoverPage(cursor: cursor) else { return }
        let existing = Set(queue.map(\.id))
        let fresh = page.candidates.filter { !existing.contains($0.id) }
        queue.append(contentsOf: fresh)
        self.cursor = page.cursor
        prefetchUpcomingPhotos()
    }

    /// Warm upcoming cards so Skip/Like advances with zero loading.
    /// Full photo sets for the next two cards + primaries a few cards ahead.
    private func prefetchUpcomingPhotos() {
        var urls: [String] = []
        for candidate in queue.prefix(3) {
            urls.append(contentsOf: candidate.photos.map(\.url))
        }
        urls.append(contentsOf: queue.prefix(6).compactMap { candidate in
            candidate.primaryPhotoURL ?? candidate.photos.first?.url
        })
        // ImageStore de-dupes repeats and in-flight downloads.
        ImagePrefetcher.prefetch(urlStrings: urls)
    }

    private func distanceLabel(_ km: Double) -> String {
        if km < 1 {
            return "< 1 km away"
        }
        return "\(Int(km.rounded())) km away"
    }
}

// MARK: - Candidate stack (Preview-aligned)

private struct DiscoverCandidateStack: View {
    let candidate: DiscoverCandidate
    var onLikeBit: ((DiscoverBit) -> Void)?

    /// Hold name/bits until the primary photo is warm — avoids a confusing half-loaded card.
    @State private var isPrimaryReady = false

    private var essentials: ProfileEssentialsCard.Model {
        ProfileEssentialsCard.Model(
            age: candidate.age,
            gender: ProfileGender.fromStored(candidate.gender)?.title ?? candidate.gender,
            city: candidate.city
        )
    }

    private var firstBit: DiscoverBit? { candidate.bits.first }

    /// photo → photo → bit → photo → bit → photo → photo (after essentials).
    private var tailBlocks: [(photo: ProfilePhoto?, bit: DiscoverBit?)] {
        ProfileStackLayout.tailBlocks(
            photos: Array(candidate.photos.dropFirst()),
            bits: Array(candidate.bits.dropFirst())
        )
    }

    private var primaryPhotoURL: String? {
        candidate.primaryPhotoURL ?? candidate.photos.first?.url
    }

    /// Cache hit → render the card synchronously, no gate.
    private var primaryIsWarm: Bool {
        guard let primaryPhotoURL else { return true }
        return ImageStore.shared.cached(primaryPhotoURL) != nil
    }

    var body: some View {
        Group {
            if isPrimaryReady || primaryIsWarm {
                profileContent
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading profile…")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: candidate.id) {
            if !primaryIsWarm {
                isPrimaryReady = false
                if let primaryPhotoURL {
                    await ImageStore.shared.load(primaryPhotoURL)
                }
            }
            isPrimaryReady = true
            // Prefetch the rest of this card in the background.
            ImagePrefetcher.prefetch(urlStrings: candidate.photos.dropFirst().map(\.url))
        }
    }

    private var profileContent: some View {
        VStack(spacing: 14) {
            Text(candidate.displayName)
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let primary = candidate.photos.first {
                ProfilePreviewPhotoTile(urlString: primary.url)
            } else {
                ProfilePreviewPhotoTile(urlString: candidate.primaryPhotoURL)
            }

            if let firstBit {
                bitCard(firstBit)
            }

            ProfileEssentialsCard(model: essentials)

            if !candidate.buddyTypes.isEmpty {
                buddyTypesRow
            }

            ForEach(Array(tailBlocks.enumerated()), id: \.offset) { _, pair in
                if let photo = pair.photo {
                    ProfilePreviewPhotoTile(urlString: photo.url)
                }
                if let bit = pair.bit {
                    bitCard(bit)
                }
            }
        }
    }

    private func bitCard(_ bit: DiscoverBit) -> some View {
        ProfilePreviewBitCard(prompt: bit.promptText, answer: bit.answerText)
            .overlay(alignment: .bottomTrailing) {
                if onLikeBit != nil {
                    Button {
                        onLikeBit?(bit)
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NADATheme.brand)
                            .padding(12)
                            .background(NADATheme.card, in: Circle())
                            .shadow(color: NADATheme.ink.opacity(0.08), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityLabel("Like this Bit")
                }
            }
    }

    private var buddyTypesRow: some View {
        FlowLayoutChips(titles: candidate.buddyTypes.map(\.title))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Simple wrapping chips for hangout types on a Discover card.
private struct FlowLayoutChips: View {
    let titles: [String]

    var body: some View {
        FlexibleChipWrap(titles: titles)
    }
}

private struct FlexibleChipWrap: View {
    let titles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hangout type")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)

            // Two-row-friendly wrap without a custom Layout dependency in this file.
            WrapHStack(spacing: 8) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        .font(NADATheme.captionFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(NADATheme.warmSecondaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NADATheme.brandSoft, in: Capsule(style: .continuous))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Minimal wrap stack for chip rows.
private struct WrapHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Optional comment when liking a profile or Bit.
private struct DiscoverLikeCommentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var isBusy = false
    let onSend: (String?) -> Void

    @State private var comment = ""

    private var trimmed: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        trimmed.count <= DiscoverLike.maxCommentLength && !isBusy
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Add a short note (optional) — hangout vibes only.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                TextField("Say why you’re down to hang…", text: $comment, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(14)
                    .background(NADATheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("\(trimmed.count)/\(DiscoverLike.maxCommentLength)")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(
                        trimmed.count > DiscoverLike.maxCommentLength
                            ? NADATheme.danger
                            : NADATheme.secondaryInk
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    onSend(trimmed.isEmpty ? nil : trimmed)
                } label: {
                    if isBusy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Send like")
                    }
                }
                .buttonStyle(NADAPrimaryButtonStyle())
                .disabled(!canSend)

                Button("Cancel") { dismiss() }
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.brandPressed)
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy)

                Spacer(minLength: 0)
            }
            .padding(24)
            .background(NADATheme.paper.ignoresSafeArea())
            .navigationTitle("Like")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DiscoverFeedView()
        .environment(AuthManager())
}
