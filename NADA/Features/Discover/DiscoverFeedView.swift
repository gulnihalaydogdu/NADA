import SwiftUI

/// One-at-a-time Discover feed — loads candidates from W3-01.
struct DiscoverFeedView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.presentMutualClickMoment) private var presentMutualClickMoment

    @State private var queue: [DiscoverCandidate] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isRefilling = false
    @State private var isSendingLike = false
    @State private var inFlightActionIds: Set<String> = []
    @State private var hasLoadedOnce = false
    @State private var localError: String?
    @State private var skippedStack: [DiscoverCandidate] = []
    @State private var commentDraft: CommentDraft?
    @State private var commentText = ""
    @FocusState private var commentFieldFocused: Bool
    @State private var catalogInterests: [Interest] = []
    @State private var likeGlow: LikeGlowTarget?
    @State private var skipBurst = false

    private static let undoCap = 10

    private var canUndo: Bool { !skippedStack.isEmpty }

    private var isActionLocked: Bool { likeGlow != nil || skipBurst }

    private var current: DiscoverCandidate? { queue.first }

    private var promptGlowId: String? {
        if case .prompt(let id) = likeGlow { return id }
        return nil
    }

    private var photoGlowId: String? {
        if case .photo(let id) = likeGlow { return id }
        return nil
    }

    private enum LikeGlowTarget: Equatable {
        case profile
        case prompt(String)
        case photo(String)
    }

    private struct CommentDraft: Equatable {
        let toUserId: String
        let targetType: DiscoverLike.TargetType
        let targetId: String

        var scrollId: String { "comment-\(targetType.rawValue)-\(targetId)" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NADAScreenBackground()

                if !auth.isProfileComplete && !auth.isResolvingProfile {
                    incompleteGate
                } else {
                    feedContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { commentFieldFocused = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NADATheme.brand)
                }
            }
            .task(id: sessionToken) {
                guard !auth.isResolvingProfile else { return }
                catalogInterests = (try? await FirestoreInterestService().fetchActiveInterests()) ?? []
                guard auth.isProfileComplete else { return }
                if auth.discoverSessionLoaded {
                    if !hasLoadedOnce || queue.isEmpty {
                        restoreSession()
                    }
                    return
                }
                await reload()
            }
            .task(id: current?.id) {
                guard let current else { return }
                await auth.recordDiscoverSeen(userId: current.id)
            }
        }
    }

    private var sessionToken: String {
        [
            auth.currentUser?.id ?? "",
            auth.isProfileComplete ? "1" : "0",
            auth.isResolvingProfile ? "1" : "0"
        ].joined(separator: "|")
    }

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
            } else if auth.isResolvingProfile && queue.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let current {
                ScrollViewReader { proxy in
                    ScrollView {
                        DiscoverCandidateStack(
                            candidate: current,
                            catalogInterests: catalogInterests,
                            viewerInterestIds: auth.currentUser?.interestIds ?? [],
                            glowingPromptId: promptGlowId,
                            glowingPhotoId: photoGlowId,
                            onLikeBit: { bit in
                                openComment(on: current, type: .prompt, targetId: bit.id)
                            },
                            onLikePhoto: { photo in
                                openComment(on: current, type: .photo, targetId: photo.id)
                            },
                            commentingPhotoId: commentDraft?.targetType == .photo ? commentDraft?.targetId : nil,
                            commentingPromptId: commentDraft?.targetType == .prompt ? commentDraft?.targetId : nil,
                            commentText: $commentText,
                            commentFocused: $commentFieldFocused,
                            isSendingComment: isSendingLike,
                            onSendComment: sendOpenComment
                        )
                        .id("discover-card")
                        .overlay { DiscoverSkipStamp(isActive: skipBurst) }
                        .offset(x: skipBurst ? -56 : 0)
                        .rotationEffect(.degrees(skipBurst ? -7 : 0))
                        .opacity(skipBurst ? 0.55 : 1)
                        .allowsHitTesting(!skipBurst)
                        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: skipBurst)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: current.id) { _, _ in
                        clearCommentComposer()
                        proxy.scrollTo("discover-card", anchor: .top)
                    }
                    .onChange(of: commentDraft?.scrollId) { _, scrollId in
                        guard let scrollId else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                proxy.scrollTo(scrollId, anchor: .bottom)
                            }
                        }
                    }
                }

                actionBar
            } else if hasLoadedOnce {
                emptyState
            } else {
                Spacer()
            }
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

            Text("Try the same city as the other account, widen age/gender in Discover preferences, or check back later.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                Task { await reload(forceNetwork: true) }
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
                    undoSkip()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(canUndo ? NADATheme.ink : NADATheme.secondaryInk)
                        .frame(width: 56, height: 56)
                        .background(NADATheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1))
                }
                .disabled(!canUndo || isActionLocked)
                .accessibilityLabel("Undo skip")

                Button {
                    skipCurrent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NADATheme.ink)
                        .frame(width: 64, height: 64)
                        .background(NADATheme.card, in: Circle())
                        .overlay(Circle().strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1))
                        .background {
                            DiscoverSkipGlow(isActive: skipBurst)
                                .frame(width: 96, height: 96)
                        }
                        .shadow(
                            color: NADATheme.ink.opacity(skipBurst ? 0.28 : 0),
                            radius: skipBurst ? 16 : 0
                        )
                        .scaleEffect(skipBurst ? 1.12 : 1)
                }
                .disabled(current == nil || isActionLocked)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: skipBurst)
                .accessibilityLabel("Skip")

                Button {
                    guard let current else { return }
                    clearCommentComposer()
                    Task {
                        await sendLike(
                            toUserId: current.id,
                            targetType: .profile,
                            targetId: current.id,
                            comment: nil
                        )
                    }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(NADATheme.onBrand)
                        .frame(width: 64, height: 64)
                        .background(NADATheme.brand, in: Circle())
                        .background {
                            DiscoverCoralGlow(isActive: likeGlow == .profile)
                                .frame(width: 96, height: 96)
                        }
                        .shadow(
                            color: NADATheme.brand.opacity(likeGlow == .profile ? 0.7 : 0),
                            radius: likeGlow == .profile ? 20 : 0
                        )
                        .scaleEffect(likeGlow == .profile ? 1.12 : 1)
                }
                .disabled(current == nil || isActionLocked)
                .buttonStyle(NADATactilePressStyle())
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: likeGlow)
                .accessibilityLabel("Click profile")
            }

            Text("Click a photo, a Bit, or the whole profile. Skip to pass — Undo brings them back.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 24, topTrailing: 24),
                style: .continuous
            )
            .fill(NADATheme.surface.opacity(0.96))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func restoreSession() {
        queue = auth.discoverSessionQueue
        cursor = auth.discoverSessionCursor
        skippedStack = auth.discoverSessionSkipped
        hasLoadedOnce = true
        prefetchUpcomingPhotos()
    }

    private func persistSession() {
        auth.rememberDiscoverSession(queue: queue, cursor: cursor, skipped: skippedStack)
    }

    private func reload(forceNetwork: Bool = false) async {
        localError = nil
        auth.clearError()
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        let page = await auth.fetchDiscoverFeed(cursor: nil, ignoreSession: forceNetwork)
        if page.isEmpty, auth.errorMessage != nil {
            localError = auth.errorMessage
        }
        queue = page.candidates
        cursor = page.cursor
        persistSession()
        prefetchUpcomingPhotos()
    }

    private func removeCurrentFromQueue() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        persistSession()
        prefetchUpcomingPhotos()
        if queue.count <= 3 {
            Task { await loadMoreIfNeeded() }
        }
    }

    private func skipCurrent() {
        guard !isActionLocked, let current, !inFlightActionIds.contains(current.id) else { return }
        clearCommentComposer()
        inFlightActionIds.insert(current.id)
        localError = nil
        skipBurst = true
        pushSkipped(current)

        Task {
            let write = Task { await auth.skipDiscoverUser(current.id) }
            try? await Task.sleep(nanoseconds: 240_000_000)
            skipBurst = false
            if queue.first?.id == current.id {
                removeCurrentFromQueue()
            }

            let skipped = await write.value
            inFlightActionIds.remove(current.id)
            if skipped == nil {
                skippedStack.removeAll { $0.id == current.id }
                recoverFailedRemoval(current)
                if auth.errorMessage == nil {
                    localError = "Couldn't skip. Try again."
                }
            }
        }
    }

    private func pushSkipped(_ candidate: DiscoverCandidate) {
        skippedStack.removeAll { $0.id == candidate.id }
        skippedStack.append(candidate)
        if skippedStack.count > Self.undoCap {
            skippedStack.removeFirst(skippedStack.count - Self.undoCap)
        }
        persistSession()
    }

    private func openComment(
        on candidate: DiscoverCandidate,
        type: DiscoverLike.TargetType,
        targetId: String
    ) {
        if commentDraft?.toUserId == candidate.id,
           commentDraft?.targetType == type,
           commentDraft?.targetId == targetId {
            clearCommentComposer()
            return
        }
        commentDraft = CommentDraft(toUserId: candidate.id, targetType: type, targetId: targetId)
        commentText = ""
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            commentFieldFocused = true
        }
    }

    private func sendOpenComment() {
        guard let commentDraft else { return }
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = trimmed.isEmpty ? nil : String(trimmed.prefix(DiscoverLike.maxCommentLength))
        Task {
            await sendLike(
                toUserId: commentDraft.toUserId,
                targetType: commentDraft.targetType,
                targetId: commentDraft.targetId,
                comment: comment
            )
        }
    }

    private func clearCommentComposer() {
        commentDraft = nil
        commentText = ""
        commentFieldFocused = false
    }

    private func sendLike(
        toUserId: String,
        targetType: DiscoverLike.TargetType,
        targetId: String,
        comment: String?
    ) async {
        guard !isSendingLike, !skipBurst, !inFlightActionIds.contains(toUserId) else { return }
        isSendingLike = true
        inFlightActionIds.insert(toUserId)
        localError = nil
        clearCommentComposer()
        isSendingLike = false

        likeGlow = glowTarget(type: targetType, targetId: targetId)
        let write = Task {
            await auth.likeDiscoverTarget(
                toUserId: toUserId,
                targetType: targetType,
                targetId: targetId,
                comment: comment
            )
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        likeGlow = nil

        var removed: DiscoverCandidate?
        if queue.first?.id == toUserId {
            removed = queue.first
            skippedStack.removeAll { $0.id == toUserId }
            removeCurrentFromQueue()
        }

        let liked = await write.value
        inFlightActionIds.remove(toUserId)
        if liked == nil {
            if let removed {
                recoverFailedRemoval(removed)
            }
            if auth.errorMessage == nil {
                localError = "Couldn't send that click."
            }
            return
        }

        if liked?.match != nil, let other = removed ?? queue.first(where: { $0.id == toUserId }) {
            let photo = other.photos.first
            await presentMutualClickMoment(
                MutualClickSnapshot(
                    viewerURL: auth.currentUser?.photoURL,
                    viewerThumb: auth.currentUser?.photoThumbnailURL,
                    otherURL: photo?.url,
                    otherThumb: photo?.thumbnailURL
                )
            )
        }
    }

    private func glowTarget(type: DiscoverLike.TargetType, targetId: String) -> LikeGlowTarget {
        switch type {
        case .profile: return .profile
        case .prompt: return .prompt(targetId)
        case .photo: return .photo(targetId)
        }
    }

    private func undoSkip() {
        guard !isActionLocked, let restored = skippedStack.popLast() else { return }
        localError = nil
        queue.removeAll { $0.id == restored.id }
        queue.insert(restored, at: 0)
        persistSession()
        prefetchUpcomingPhotos()

        Task {
            let ok = await auth.undoDiscoverSkip(toUserId: restored.id)
            if !ok {
                queue.removeAll { $0.id == restored.id }
                skippedStack.append(restored)
                persistSession()
                prefetchUpcomingPhotos()
                if auth.errorMessage == nil {
                    localError = "Nothing to undo."
                }
            }
        }
    }

    /// Skip/like already advanced the card — don't yank the new profile if the write fails.
    private func recoverFailedRemoval(_ candidate: DiscoverCandidate) {
        guard !queue.contains(where: { $0.id == candidate.id }) else {
            persistSession()
            prefetchUpcomingPhotos()
            return
        }
        if queue.isEmpty {
            queue.insert(candidate, at: 0)
        } else {
            queue.insert(candidate, at: 1)
        }
        persistSession()
        prefetchUpcomingPhotos()
    }

    private func loadMoreIfNeeded() async {
        guard let cursor, !isRefilling, !isLoading else { return }
        isRefilling = true
        defer { isRefilling = false }

        let page = await auth.fetchDiscoverFeed(
            extraExcludedUserIds: Set(queue.map(\.id)),
            cursor: cursor
        )
        let existing = Set(queue.map(\.id))
        queue.append(contentsOf: page.candidates.filter { !existing.contains($0.id) })
        self.cursor = page.cursor
        persistSession()
        prefetchUpcomingPhotos()
    }

    /// Priority: next primary → current 2nd photo → after-next primary → a few thumbs.
    private func prefetchUpcomingPhotos() {
        let current = queue.first
        let next = queue.count > 1 ? queue[1] : nil
        let afterNext = queue.count > 2 ? queue[2] : nil
        let photoSize = ProfilePreviewPhotoTile.displayPointSize
        let thumbSize = RemoteImageView.thumbnailPointSize

        var ordered: [(urlString: String, targetPointSize: CGFloat)] = []

        if let photo = next?.photos.first {
            ordered.append((photo.url, photoSize))
        }
        if let photo = current?.photos.dropFirst().first {
            ordered.append((photo.url, photoSize))
        }
        if let photo = afterNext?.photos.first {
            ordered.append((photo.url, photoSize))
        }
        if let next {
            for photo in next.photos.dropFirst().prefix(2) {
                ordered.append((photo.thumbnailURL ?? photo.previewURL, thumbSize))
            }
        }
        if let afterNext, let thumb = afterNext.photos.first?.thumbnailURL
            ?? afterNext.photos.first?.previewURL {
            ordered.append((thumb, thumbSize))
        }

        RemoteImageLoader.shared.prefetchOrdered(ordered)
    }

    private func distanceLabel(_ km: Double) -> String {
        if km < 1 { return "< 1 km away" }
        return "\(Int(km.rounded())) km away"
    }
}

struct DiscoverCandidateStack: View {
    let candidate: DiscoverCandidate
    let catalogInterests: [Interest]
    var viewerInterestIds: [String] = []
    var glowingPromptId: String? = nil
    var glowingPhotoId: String? = nil
    var onLikeBit: ((DiscoverBit) -> Void)?
    var onLikePhoto: ((ProfilePhoto) -> Void)?
    var commentingPhotoId: String? = nil
    var commentingPromptId: String? = nil
    var commentText: Binding<String> = .constant("")
    var commentFocused: FocusState<Bool>.Binding? = nil
    var isSendingComment = false
    var onSendComment: (() -> Void)? = nil
    var highlightedPhotoId: String? = nil
    var highlightedPromptId: String? = nil
    var highlightLabel: String? = nil
    var showsName: Bool = true

    private var essentials: ProfileEssentialsCard.Model {
        ProfileEssentialsCard.Model(
            age: candidate.age,
            gender: ProfileGender.fromStored(candidate.gender)?.title ?? candidate.gender,
            city: candidate.city,
            jobTitle: candidate.jobTitle,
            university: candidate.university,
            hangoutLookingFor: candidate.hangoutLookingFor
        )
    }

    private var previewInterests: [Interest] {
        let byId = Dictionary(uniqueKeysWithValues: catalogInterests.map { ($0.id, $0) })
        return candidate.interestIds.compactMap { byId[$0] }
    }

    private var firstBit: DiscoverBit? { candidate.bits.first }

    var body: some View {
        VStack(spacing: 16) {
            if showsName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.displayName)
                        .font(NADATheme.displayFont)
                        .foregroundStyle(NADATheme.ink)
                    ProfileZodiacCaption(sign: candidate.zodiac)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let primary = candidate.photos.first {
                photoBlock(primary)
            } else {
                ProfilePreviewPhotoTile(urlString: nil)
            }

            if let firstBit {
                bitBlock(firstBit)
            }

            ProfileEssentialsCard(model: essentials)
            DiscoverInterestOverlapView(
                interests: previewInterests,
                viewerInterestIds: viewerInterestIds
            )

            let remainingPhotos = Array(candidate.photos.dropFirst())
            let remainingBits = Array(candidate.bits.dropFirst())
            let tail = ProfileStackRhythm.tail(photos: remainingPhotos, bits: remainingBits)
            LazyVStack(spacing: 16) {
                ForEach(Array(tail.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .photo(let photo):
                        photoBlock(photo)
                    case .bit(let bit):
                        bitBlock(bit)
                    }
                }
            }
        }
    }

    private func photoBlock(_ photo: ProfilePhoto) -> some View {
        let isCommenting = commentingPhotoId == photo.id
        return VStack(spacing: isCommenting ? 12 : 0) {
            photoCard(photo, framed: isCommenting)
            if isCommenting {
                inlineCommentBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .id("comment-photo-\(photo.id)")
            }
        }
        .padding(.top, isCommenting ? 12 : 0)
        .padding(.horizontal, isCommenting ? 12 : 0)
        .background {
            if isCommenting {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NADATheme.card)
            }
        }
        .overlay {
            if isCommenting {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        glowingPhotoId == photo.id
                            ? NADATheme.brand.opacity(0.85)
                            : NADATheme.hairline.opacity(0.38),
                        lineWidth: glowingPhotoId == photo.id ? 3 : 1
                    )
            }
        }
        .id("photo-\(photo.id)")
        .animation(.easeOut(duration: 0.14), value: commentingPhotoId)
    }

    private func bitBlock(_ bit: DiscoverBit) -> some View {
        let isCommenting = commentingPromptId == bit.id
        return VStack(alignment: .leading, spacing: isCommenting ? 12 : 0) {
            bitCard(bit, showsChrome: !isCommenting)
                .padding(.horizontal, isCommenting ? 20 : 0)
                .padding(.top, isCommenting ? 20 : 0)
            if isCommenting {
                inlineCommentBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .id("comment-prompt-\(bit.id)")
            }
        }
        .background {
            if isCommenting {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NADATheme.card)
            }
        }
        .overlay {
            if isCommenting {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        glowingPromptId == bit.id
                            ? NADATheme.brand.opacity(0.85)
                            : NADATheme.hairline.opacity(0.38),
                        lineWidth: glowingPromptId == bit.id ? 3 : 1
                    )
            }
        }
        .id("prompt-\(bit.id)")
        .animation(.easeOut(duration: 0.14), value: commentingPromptId)
    }

    @ViewBuilder
    private var inlineCommentBar: some View {
        DiscoverInlineCommentBar(
            text: commentText,
            focused: commentFocused,
            isBusy: isSendingComment,
            onSend: { onSendComment?() }
        )
    }

    private func photoCard(_ photo: ProfilePhoto, framed: Bool) -> some View {
        let isHighlighted = highlightedPhotoId == photo.id
        let showStroke = !framed && (glowingPhotoId == photo.id || isHighlighted)
        return ProfilePreviewPhotoTile(
            urlString: photo.url,
            thumbnailURLString: photo.thumbnailURL,
            cornerRadius: framed ? 16 : 22
        )
        .overlay(alignment: .topLeading) {
            if isHighlighted, let highlightLabel {
                likeHighlightChip(highlightLabel)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if onLikePhoto != nil, !framed {
                DiscoverLikeHeartButton(
                    isGlowing: glowingPhotoId == photo.id,
                    accessibilityLabel: "Click this photo"
                ) {
                    onLikePhoto?(photo)
                }
                .padding(12)
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: framed ? 16 : 22, style: .continuous)
                .strokeBorder(
                    NADATheme.brand.opacity(showStroke ? (glowingPhotoId == photo.id ? 0.85 : 0.55) : 0),
                    lineWidth: showStroke ? 3 : 0
                )
                .shadow(color: NADATheme.brand.opacity(!framed && glowingPhotoId == photo.id ? 0.55 : 0), radius: 18)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: glowingPhotoId)
        }
    }

    private func bitCard(_ bit: DiscoverBit, showsChrome: Bool) -> some View {
        let isHighlighted = highlightedPromptId == bit.id
        let showStroke = showsChrome && (glowingPromptId == bit.id || isHighlighted)
        return ProfilePreviewBitCard(
            prompt: bit.promptText,
            answer: bit.answerText,
            showsChrome: showsChrome
        )
            .overlay(alignment: .topLeading) {
                if isHighlighted, let highlightLabel {
                    likeHighlightChip(highlightLabel)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if onLikeBit != nil, showsChrome {
                    DiscoverLikeHeartButton(
                        isGlowing: glowingPromptId == bit.id,
                        accessibilityLabel: "Click this Bit"
                    ) {
                        onLikeBit?(bit)
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        NADATheme.brand.opacity(showStroke ? (glowingPromptId == bit.id ? 0.85 : 0.55) : 0),
                        lineWidth: showStroke ? 3 : 0
                    )
                    .shadow(color: NADATheme.brand.opacity(showsChrome && glowingPromptId == bit.id ? 0.55 : 0), radius: 18)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: glowingPromptId)
            }
    }

    private func likeHighlightChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NADATheme.onBrand)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NADATheme.brand, in: Capsule())
            .padding(12)
    }
}

private struct DiscoverCoralGlow: View {
    var isActive: Bool

    var body: some View {
        Circle()
            .fill(NADATheme.brand.opacity(isActive ? 0.5 : 0))
            .blur(radius: isActive ? 16 : 0)
            .scaleEffect(isActive ? 1.85 : 0.65)
            .allowsHitTesting(false)
    }
}

private struct DiscoverSkipGlow: View {
    var isActive: Bool

    var body: some View {
        Circle()
            .fill(NADATheme.ink.opacity(isActive ? 0.22 : 0))
            .blur(radius: isActive ? 14 : 0)
            .scaleEffect(isActive ? 1.85 : 0.65)
            .allowsHitTesting(false)
    }
}

private struct DiscoverSkipStamp: View {
    var isActive: Bool

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 72, weight: .bold))
            .foregroundStyle(NADATheme.ink.opacity(isActive ? 0.42 : 0))
            .scaleEffect(isActive ? 1 : 0.45)
            .allowsHitTesting(false)
    }
}

private struct DiscoverInlineCommentBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding?
    var isBusy: Bool
    var onSend: () -> Void

    private var canSend: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count <= DiscoverLike.maxCommentLength
            && !isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let focused {
                    field.focused(focused)
                } else {
                    field
                }
            }

            Button(action: onSend) {
                Text("Send click")
            }
            .buttonStyle(NADASoftCapsuleButtonStyle())
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.55)
        }
        .padding(.top, 0)
    }

    private var field: some View {
        TextField("Add a comment", text: $text, axis: .vertical)
            .font(NADATheme.bodyFont)
            .foregroundStyle(NADATheme.ink)
            .lineLimit(1...4)
            .submitLabel(.done)
            .onSubmit { focused?.wrappedValue = false }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(NADATheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.8), lineWidth: 1)
            }
    }
}

private struct DiscoverLikeHeartButton: View {
    var isGlowing: Bool
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isGlowing ? NADATheme.onBrand : NADATheme.brand)
                .padding(12)
                .background(isGlowing ? NADATheme.brand : NADATheme.card, in: Circle())
                .overlay {
                    DiscoverCoralGlow(isActive: isGlowing)
                }
                .shadow(
                    color: isGlowing ? NADATheme.brand.opacity(0.7) : NADATheme.ink.opacity(0.08),
                    radius: isGlowing ? 16 : 4,
                    y: 2
                )
                .scaleEffect(isGlowing ? 1.18 : 1)
        }
        .buttonStyle(NADATactilePressStyle())
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isGlowing)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    DiscoverFeedView()
        .environment(AuthManager())
}
