import SwiftUI

/// One-at-a-time Discover feed — loads candidates from W3-01.
struct DiscoverFeedView: View {
    @Environment(AuthManager.self) private var auth

    @State private var queue: [DiscoverCandidate] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var isActing = false
    @State private var hasLoadedOnce = false
    @State private var localError: String?
    @State private var lastSkipped: DiscoverCandidate?
    @State private var likeDraft: LikeDraft?
    @State private var catalogInterests: [Interest] = []

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
                ScrollView {
                    DiscoverCandidateStack(
                        candidate: current,
                        catalogInterests: catalogInterests,
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

                actionBar
            } else if hasLoadedOnce {
                emptyState
            } else {
                Spacer()
            }
        }
        .sheet(item: $likeDraft) { draft in
            DiscoverLikeCommentSheet(title: draft.title, isBusy: isActing) { comment in
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
        } else if auth.errorMessage == nil {
            localError = "Nothing to undo."
        }
    }

    private func loadMoreIfNeeded() async {
        guard let cursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let page = await auth.fetchDiscoverFeed(
            extraExcludedUserIds: Set(queue.map(\.id)),
            cursor: cursor
        )
        let existing = Set(queue.map(\.id))
        queue.append(contentsOf: page.candidates.filter { !existing.contains($0.id) })
        self.cursor = page.cursor
        prefetchUpcomingPhotos()
    }

    private func prefetchUpcomingPhotos() {
        let urls = queue.prefix(3).flatMap { candidate in
            candidate.photos.map(\.url)
        }
        RemoteImageLoader.shared.prefetch(urlStrings: Array(urls), targetPointSize: 430, limit: 6)
    }

    private func distanceLabel(_ km: Double) -> String {
        if km < 1 { return "< 1 km away" }
        return "\(Int(km.rounded())) km away"
    }
}

private struct DiscoverCandidateStack: View {
    let candidate: DiscoverCandidate
    let catalogInterests: [Interest]
    var onLikeBit: ((DiscoverBit) -> Void)?

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
                ProfilePreviewPhotoTile(
                    urlString: primary.url,
                    thumbnailURLString: primary.thumbnailURL
                )
            } else {
                ProfilePreviewPhotoTile(urlString: nil)
            }

            if let firstBit {
                bitCard(firstBit)
            }

            ProfileEssentialsCard(model: essentials)
            ProfileInterestBadgesView(interests: previewInterests)

            let remainingPhotos = Array(candidate.photos.dropFirst())
            let remainingBits = Array(candidate.bits.dropFirst())
            let count = max(remainingPhotos.count, remainingBits.count)
            ForEach(0..<count, id: \.self) { index in
                if index < remainingPhotos.count {
                    ProfilePreviewPhotoTile(
                        urlString: remainingPhotos[index].url,
                        thumbnailURLString: remainingPhotos[index].thumbnailURL
                    )
                }
                if index < remainingBits.count {
                    bitCard(remainingBits[index])
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
