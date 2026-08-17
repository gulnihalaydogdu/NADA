import SwiftUI

/// One-at-a-time Discover feed — loads candidates from W3-01.
struct DiscoverFeedView: View {
    @Environment(AuthManager.self) private var auth

    @State private var queue: [DiscoverCandidate] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isRefilling = false
    @State private var isSendingLike = false
    @State private var inFlightActionIds: Set<String> = []
    @State private var hasLoadedOnce = false
    @State private var localError: String?
    @State private var skippedStack: [DiscoverCandidate] = []
    @State private var likeDraft: LikeDraft?
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

            if !auth.isProfileComplete && !auth.isResolvingProfile {
                incompleteGate
            } else {
                feedContent
            }
        }
        .task(id: reloadToken) {
            guard !auth.isResolvingProfile else { return }
            catalogInterests = (try? await FirestoreInterestService().fetchActiveInterests()) ?? []
            guard auth.isProfileComplete else { return }
            await reload()
        }
        .task(id: current?.id) {
            guard let current else { return }
            await auth.recordDiscoverSeen(userId: current.id)
        }
    }

    private var reloadToken: String {
        [
            auth.currentUser?.id ?? "",
            auth.isProfileComplete ? "1" : "0",
            auth.isResolvingProfile ? "1" : "0",
            auth.currentPreferences == nil ? "0" : "1"
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
                                likeDraft = LikeDraft(
                                    toUserId: current.id,
                                    targetType: .prompt,
                                    targetId: bit.id,
                                    title: bit.promptText
                                )
                            },
                            onLikePhoto: { photo in
                                likeDraft = LikeDraft(
                                    toUserId: current.id,
                                    targetType: .photo,
                                    targetId: photo.id,
                                    title: "This photo"
                                )
                            }
                        )
                        .id("discover-card")
                        .overlay { DiscoverSkipStamp(isActive: skipBurst) }
                        .offset(x: skipBurst ? -56 : 0)
                        .rotationEffect(.degrees(skipBurst ? -7 : 0))
                        .opacity(skipBurst ? 0.55 : 1)
                        .allowsHitTesting(!skipBurst)
                        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: skipBurst)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .onChange(of: current.id) { _, _ in
                        proxy.scrollTo("discover-card", anchor: .top)
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
            DiscoverLikeCommentSheet(title: draft.title, isBusy: isSendingLike) { comment in
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

            Text("Try the same city as the other account, widen age/gender in Discover preferences, or check back later.")
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
                .animation(.spring(response: 0.34, dampingFraction: 0.62), value: skipBurst)
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
                .animation(.spring(response: 0.34, dampingFraction: 0.62), value: likeGlow)
                .accessibilityLabel("Like profile")
            }

            Text("Like a photo, a Bit, or the whole profile. Skip to pass — Undo brings them back.")
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

    private func reload() async {
        localError = nil
        auth.clearError()
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        let page = await auth.fetchDiscoverFeed(cursor: nil)
        if page.isEmpty, auth.errorMessage != nil {
            localError = auth.errorMessage
        }
        queue = page.candidates
        cursor = page.cursor
        prefetchUpcomingPhotos()
    }

    private func removeCurrentFromQueue() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        prefetchUpcomingPhotos()
        if queue.count <= 3 {
            Task { await loadMoreIfNeeded() }
        }
    }

    private func skipCurrent() {
        guard !isActionLocked, let current, !inFlightActionIds.contains(current.id) else { return }
        inFlightActionIds.insert(current.id)
        localError = nil
        skipBurst = true
        pushSkipped(current)

        Task {
            let write = Task { await auth.skipDiscoverUser(current.id) }
            try? await Task.sleep(nanoseconds: 380_000_000)
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
        likeDraft = nil
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
        try? await Task.sleep(nanoseconds: 420_000_000)
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
                localError = "Couldn't send that like."
            }
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
        prefetchUpcomingPhotos()

        Task {
            let ok = await auth.undoDiscoverSkip(toUserId: restored.id)
            if !ok {
                queue.removeAll { $0.id == restored.id }
                skippedStack.append(restored)
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
            prefetchUpcomingPhotos()
            return
        }
        if queue.isEmpty {
            queue.insert(candidate, at: 0)
        } else {
            queue.insert(candidate, at: 1)
        }
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

private struct DiscoverCandidateStack: View {
    let candidate: DiscoverCandidate
    let catalogInterests: [Interest]
    var viewerInterestIds: [String] = []
    var glowingPromptId: String? = nil
    var glowingPhotoId: String? = nil
    var onLikeBit: ((DiscoverBit) -> Void)?
    var onLikePhoto: ((ProfilePhoto) -> Void)?

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
        VStack(spacing: 14) {
            Text(candidate.displayName)
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let primary = candidate.photos.first {
                photoCard(primary)
            } else {
                ProfilePreviewPhotoTile(urlString: nil)
            }

            if let firstBit {
                bitCard(firstBit)
            }

            ProfileEssentialsCard(model: essentials)
            DiscoverInterestOverlapView(
                interests: previewInterests,
                viewerInterestIds: viewerInterestIds
            )

            let remainingPhotos = Array(candidate.photos.dropFirst())
            let remainingBits = Array(candidate.bits.dropFirst())
            let count = max(remainingPhotos.count, remainingBits.count)
            LazyVStack(spacing: 14) {
                ForEach(0..<count, id: \.self) { index in
                    if index < remainingPhotos.count {
                        photoCard(remainingPhotos[index])
                    }
                    if index < remainingBits.count {
                        bitCard(remainingBits[index])
                    }
                }
            }
        }
    }

    private func photoCard(_ photo: ProfilePhoto) -> some View {
        ProfilePreviewPhotoTile(
            urlString: photo.url,
            thumbnailURLString: photo.thumbnailURL
        )
        .overlay(alignment: .bottomTrailing) {
            if onLikePhoto != nil {
                DiscoverLikeHeartButton(
                    isGlowing: glowingPhotoId == photo.id,
                    accessibilityLabel: "Like this photo"
                ) {
                    onLikePhoto?(photo)
                }
                .padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NADATheme.brand.opacity(glowingPhotoId == photo.id ? 0.85 : 0), lineWidth: 3)
                .shadow(color: NADATheme.brand.opacity(glowingPhotoId == photo.id ? 0.55 : 0), radius: 18)
                .animation(.spring(response: 0.34, dampingFraction: 0.62), value: glowingPhotoId)
        }
    }

    private func bitCard(_ bit: DiscoverBit) -> some View {
        ProfilePreviewBitCard(prompt: bit.promptText, answer: bit.answerText)
            .overlay(alignment: .bottomTrailing) {
                if onLikeBit != nil {
                    DiscoverLikeHeartButton(
                        isGlowing: glowingPromptId == bit.id,
                        accessibilityLabel: "Like this Bit"
                    ) {
                        onLikeBit?(bit)
                    }
                    .padding(12)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(NADATheme.brand.opacity(glowingPromptId == bit.id ? 0.85 : 0), lineWidth: 3)
                    .shadow(color: NADATheme.brand.opacity(glowingPromptId == bit.id ? 0.55 : 0), radius: 18)
                    .animation(.spring(response: 0.34, dampingFraction: 0.62), value: glowingPromptId)
            }
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
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: isGlowing)
        .accessibilityLabel(accessibilityLabel)
    }
}

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
