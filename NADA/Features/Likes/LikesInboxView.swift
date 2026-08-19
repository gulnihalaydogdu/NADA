import SwiftUI

/// Likes inbox (W4-05) — people who liked you. Sent likes stay private;
/// a like-back moves the pair to Matches.
struct LikesInboxView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.presentMutualClickMoment) private var presentMutualClickMoment

    @State private var incoming = InboxSection()
    @State private var pendingUserIds: Set<String> = []
    @State private var glowLikeId: String?
    @State private var likeBackDraft: LikeBackDraft?
    @State private var isSendingLikeBack = false
    @State private var localError: String?
    @State private var openedItem: InboxLike?
    @State private var openedCandidate: DiscoverCandidate?
    @State private var isLoadingProfile = false
    @State private var catalogInterests: [Interest] = []
    @State private var candidateCache: [String: DiscoverCandidate] = [:]

    private struct LikeBackDraft: Identifiable {
        let item: InboxLike
        var id: String { item.id }
    }

    private struct InboxSection {
        var items: [InboxLike] = []
        var cursor: String?
        var hasLoaded = false
        var isLoading = false
        var isPaging = false
    }

    private var section: InboxSection { incoming }

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            VStack(spacing: 0) {
                if let openedItem {
                    LikeInboxProfileView(
                        item: openedItem,
                        candidate: openedCandidate,
                        isLoading: isLoadingProfile,
                        catalogInterests: catalogInterests,
                        viewerInterestIds: auth.currentUser?.interestIds ?? [],
                        isPending: pendingUserIds.contains(openedItem.otherUser.id),
                        isGlowing: glowLikeId == openedItem.id,
                        onAll: closeProfile,
                        onLikeBack: { presentLikeBack(openedItem) },
                        onPass: { pass(openedItem) }
                    )
                } else {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    if let message = localError ?? auth.errorMessage {
                        Text(message)
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    content
                }
            }

            if let draft = likeBackDraft {
                ClickBackConnectionView(
                    name: draft.item.otherUser.displayName,
                    target: draft.item.target,
                    incomingComment: draft.item.like.comment,
                    otherPhotoURL: draft.item.otherUser.photoURL,
                    otherPhotoThumbnailURL: draft.item.otherUser.photoThumbnailURL,
                    isBusy: isSendingLikeBack,
                    onSend: { comment in
                        Task { await sendLikeBack(draft: draft, comment: comment) }
                    },
                    onDismiss: { likeBackDraft = nil }
                )
                .zIndex(10)
            }
        }
        .task(id: loadToken) {
            Task {
                catalogInterests = (try? await FirestoreInterestService().fetchActiveInterests()) ?? catalogInterests
            }
            await loadInitial()
        }
    }

    private var loadToken: String {
        auth.currentUser?.id ?? ""
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Clicks")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
            Spacer()
            if auth.incomingLikerCount > 0 {
                Text(auth.incomingLikerCount == 1 ? "1 new click" : "\(auth.incomingLikerCount) new clicks")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let state = section

        if state.isLoading, state.items.isEmpty {
            Spacer()
            ProgressView()
                .tint(NADATheme.brandPressed)
            Spacer()
        } else if state.items.isEmpty, state.hasLoaded {
            emptyState
        } else if state.items.isEmpty {
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(state.items) { item in
                        LikeInboxRow(
                            item: item,
                            isPending: pendingUserIds.contains(item.otherUser.id),
                            isGlowing: glowLikeId == item.id,
                            onOpen: { openProfile(item) },
                            onLikeBack: { presentLikeBack(item) },
                            onPass: { pass(item) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.94).combined(with: .opacity)
                        ))
                    }

                    if state.cursor != nil {
                        ProgressView()
                            .tint(NADATheme.brandPressed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .task(id: state.cursor) {
                                await loadMore()
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await reload()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "heart")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(20)
                .background(NADATheme.brandSoft, in: Circle())

            Text("No clicks yet")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)

            Text("When someone clicks your photo, a Bit, or your whole profile, it lands right here.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button("Refresh") {
                Task { await reload() }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .padding(.horizontal, 48)
            .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Loading

    private func loadInitial() async {
        guard auth.currentUser != nil else { return }
        if let cached = auth.cachedLikeInbox(direction: .incoming), !cached.items.isEmpty {
            apply(cached, replacing: true, prefetch: section.items.isEmpty)
            let page = await fetchPage(cursor: nil)
            apply(page, replacing: true, prefetch: true)
            return
        }
        guard !section.hasLoaded else {
            let page = await fetchPage(cursor: nil)
            apply(page, replacing: true, prefetch: true)
            return
        }
        guard !section.isLoading else { return }
        setLoading(true)
        let page = await fetchPage(cursor: nil)
        apply(page, replacing: true, prefetch: true)
    }

    private func reload() async {
        guard auth.currentUser != nil else { return }
        localError = nil
        let page = await fetchPage(cursor: nil)
        apply(page, replacing: true, prefetch: true)
    }

    private func loadMore() async {
        guard let cursor = section.cursor, !section.isPaging else { return }
        setPaging(true)
        let page = await fetchPage(cursor: cursor)
        apply(page, replacing: false, prefetch: true)
    }

    private func fetchPage(cursor: String?) async -> LikeInboxPage {
        await auth.fetchIncomingLikes(cursor: cursor)
    }

    private func apply(_ page: LikeInboxPage, replacing: Bool, prefetch: Bool) {
        var state = section
        if replacing {
            state.items = page.items
        } else {
            let known = Set(state.items.map(\.id))
            state.items.append(contentsOf: page.items.filter { !known.contains($0.id) })
        }
        state.cursor = page.cursor
        state.hasLoaded = true
        state.isLoading = false
        state.isPaging = false
        write(state)
        guard prefetch else { return }
        prefetchThumbnails(page.items)
        prefetchFirstProfile(page.items)
    }

    private func setLoading(_ value: Bool) {
        var state = section
        state.isLoading = value
        write(state)
    }

    private func setPaging(_ value: Bool) {
        var state = section
        state.isPaging = value
        write(state)
    }

    private func write(_ state: InboxSection) {
        incoming = state
    }

    /// First three avatars, then liked-photo thumbs — never full-res gallery files.
    private func prefetchThumbnails(_ items: [InboxLike]) {
        let size = RemoteImageView.thumbnailPointSize
        var ordered: [(urlString: String, targetPointSize: CGFloat)] = []
        for item in items.prefix(3) {
            if let avatar = item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL {
                ordered.append((avatar, size))
            }
        }
        for item in items.dropFirst(3).prefix(5) {
            if let avatar = item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL {
                ordered.append((avatar, size))
            }
        }
        for item in items.prefix(3) {
            if let photo = item.target.photoThumbnailURL ?? item.target.photoURL {
                ordered.append((photo, size))
            }
        }
        RemoteImageLoader.shared.prefetchOrdered(ordered)
    }

    /// Only the first opened-profile candidate — extra full profiles starve card images.
    private func prefetchFirstProfile(_ items: [InboxLike]) {
        guard let id = items.first?.otherUser.id, candidateCache[id] == nil else { return }
        Task {
            guard let candidate = await auth.fetchInboxProfile(userId: id) else { return }
            candidateCache[id] = candidate
            prefetchProfilePhotos(candidate)
        }
    }

    // MARK: - Actions

    private func openProfile(_ item: InboxLike) {
        localError = nil
        let userId = item.otherUser.id
        let cached = candidateCache[userId]
        openedCandidate = cached
        isLoadingProfile = cached == nil
        withAnimation(.easeInOut(duration: 0.2)) {
            openedItem = item
        }
        if let cached {
            prefetchProfilePhotos(cached)
        } else {
            Task {
                let candidate = await auth.fetchInboxProfile(userId: userId)
                if let candidate {
                    candidateCache[userId] = candidate
                    prefetchProfilePhotos(candidate)
                }
                guard openedItem?.otherUser.id == userId else { return }
                openedCandidate = candidate
                isLoadingProfile = false
                if candidate == nil {
                    localError = "Couldn't load that profile. Try again."
                }
            }
        }
        if let nextId = section.items.first(where: { $0.otherUser.id != userId })?.otherUser.id,
           candidateCache[nextId] == nil {
            Task {
                guard let candidate = await auth.fetchInboxProfile(userId: nextId) else { return }
                candidateCache[nextId] = candidate
            }
        }
    }

    private func closeProfile() {
        withAnimation(.easeInOut(duration: 0.2)) {
            openedItem = nil
            openedCandidate = nil
            isLoadingProfile = false
        }
    }

    private func prefetchProfilePhotos(_ candidate: DiscoverCandidate) {
        guard let first = candidate.photos.first else { return }
        var ordered: [(urlString: String, targetPointSize: CGFloat)] = []
        if let thumb = first.thumbnailURL, !thumb.isEmpty {
            ordered.append((thumb, RemoteImageView.thumbnailPointSize))
        }
        ordered.append((first.url, ProfilePreviewPhotoTile.displayPointSize))
        for photo in candidate.photos.dropFirst().prefix(2) {
            let url = photo.thumbnailURL ?? photo.url
            ordered.append((url, RemoteImageView.thumbnailPointSize))
        }
        RemoteImageLoader.shared.prefetchOrdered(ordered)
    }

    private func presentLikeBack(_ item: InboxLike) {
        let userId = item.otherUser.id
        guard !pendingUserIds.contains(userId) else { return }
        likeBackDraft = LikeBackDraft(item: item)
    }

    private func sendLikeBack(draft: LikeBackDraft, comment: String?) async {
        let userId = draft.item.otherUser.id
        guard !pendingUserIds.contains(userId), !isSendingLikeBack else { return }
        pendingUserIds.insert(userId)
        isSendingLikeBack = true
        localError = nil
        likeBackDraft = nil
        isSendingLikeBack = false
        let removed = removeRows(userId: userId)
        closeProfile()

        let created = await auth.likeDiscoverTarget(
            toUserId: userId,
            targetType: .profile,
            targetId: userId,
            comment: comment
        )
        pendingUserIds.remove(userId)

        guard created != nil else {
            restoreRows(removed)
            if auth.errorMessage == nil {
                localError = "Couldn't send that click. Try again."
            }
            return
        }

        await presentMutualClickMoment(
            MutualClickSnapshot(
                viewerURL: auth.currentUser?.photoURL,
                viewerThumb: auth.currentUser?.photoThumbnailURL,
                otherURL: draft.item.otherUser.photoURL,
                otherThumb: draft.item.otherUser.photoThumbnailURL
            )
        )
    }

    private func pass(_ item: InboxLike) {
        let userId = item.otherUser.id
        guard !pendingUserIds.contains(userId) else { return }
        pendingUserIds.insert(userId)
        localError = nil
        let removed = removeRows(userId: userId)
        closeProfile()

        Task {
            let skipped = await auth.skipDiscoverUser(userId)
            pendingUserIds.remove(userId)
            guard skipped != nil else {
                restoreRows(removed)
                if auth.errorMessage == nil {
                    localError = "Couldn't pass. Try again."
                }
                return
            }
        }
    }

    @discardableResult
    private func removeRows(userId: String) -> [InboxLike] {
        var state = section
        let removed = state.items.filter { $0.otherUser.id == userId }
        state.items.removeAll { $0.otherUser.id == userId }
        withAnimation(.easeOut(duration: 0.22)) {
            write(state)
        }
        return removed
    }

    private func restoreRows(_ items: [InboxLike]) {
        guard !items.isEmpty else { return }
        var state = section
        let known = Set(state.items.map(\.id))
        state.items.insert(contentsOf: items.filter { !known.contains($0.id) }, at: 0)
        write(state)
    }
}

// MARK: - Row

private struct LikeInboxRow: View {
    let item: InboxLike
    let isPending: Bool
    let isGlowing: Bool
    let onOpen: () -> Void
    let onLikeBack: () -> Void
    let onPass: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        LikeAvatarView(
                            urlString: item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL,
                            thumbnailURLString: item.otherUser.photoThumbnailURL
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.otherUser.displayName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(NADATheme.ink)
                                .lineLimit(1)

                            Text(subtitle)
                                .font(NADATheme.captionFont)
                                .foregroundStyle(NADATheme.warmSecondaryInk)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if let timeLabel {
                            Text(timeLabel)
                                .font(NADATheme.captionFont)
                                .foregroundStyle(NADATheme.secondaryInk)
                        }
                    }

                    LikeInboxTargetPreview(target: item.target)

                    if let comment = item.like.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !comment.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Capsule()
                                .fill(NADATheme.brand.opacity(0.55))
                                .frame(width: 3)
                            Text(comment)
                                .font(.system(size: 15))
                                .foregroundStyle(NADATheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile")

            actions
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 14)
        }
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isGlowing ? NADATheme.brand.opacity(0.6) : NADATheme.hairline.opacity(0.7),
                    lineWidth: isGlowing ? 2 : 1
                )
        }
        .shadow(
            color: isGlowing ? NADATheme.brand.opacity(0.3) : NADATheme.ink.opacity(0.05),
            radius: isGlowing ? 18 : 8,
            y: 4
        )
        .scaleEffect(isGlowing ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isGlowing)
    }

    private var subtitle: String {
        let thing: String
        switch item.target.type {
        case .photo: thing = "photo"
        case .prompt: thing = "Bit"
        case .profile: thing = "profile"
        }
        return "clicked your \(thing)"
    }

    private var timeLabel: String? {
        guard let date = item.like.createdAt else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Pass", action: onPass)
                .buttonStyle(LikeInboxCapsuleStyle(kind: .soft))
                .disabled(isPending)

            Button {
                onLikeBack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click back")
                }
            }
            .buttonStyle(LikeInboxCapsuleStyle(kind: .brand))
            .disabled(isPending)
        }
        .opacity(isPending && !isGlowing ? 0.6 : 1)
    }
}

private struct LikeAvatarView: View {
    let urlString: String?
    let thumbnailURLString: String?

    var body: some View {
        Group {
            if urlString?.isEmpty == false {
                RemoteImageView(
                    urlString: urlString,
                    thumbnailURLString: thumbnailURLString,
                    targetPointSize: RemoteImageView.thumbnailPointSize
                )
            } else {
                ZStack {
                    NADATheme.brandSoft
                    Image(systemName: "person.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(NADATheme.brand)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(NADATheme.hairline.opacity(0.8), lineWidth: 1))
    }
}

private struct LikeInboxCapsuleStyle: ButtonStyle {
    enum Kind {
        case soft
        case brand
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(kind == .brand ? NADATheme.onBrand : NADATheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                switch kind {
                case .soft:
                    Capsule().fill(configuration.isPressed ? NADATheme.hairline : NADATheme.surface)
                case .brand:
                    Capsule().fill(configuration.isPressed ? NADATheme.brandPressed : NADATheme.brand)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.09)
                    : .spring(response: 0.22, dampingFraction: 0.86),
                value: configuration.isPressed
            )
    }
}

// MARK: - Profile (Hinge-style)

private struct LikeInboxProfileView: View {
    let item: InboxLike
    let candidate: DiscoverCandidate?
    let isLoading: Bool
    let catalogInterests: [Interest]
    let viewerInterestIds: [String]
    let isPending: Bool
    let isGlowing: Bool
    let onAll: () -> Void
    let onLikeBack: () -> Void
    let onPass: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                    header
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                if let candidate {
                    profileScroll(candidate)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            likeContextCard
                            ProfilePreviewPhotoTile(
                                urlString: item.otherUser.photoURL,
                                thumbnailURLString: item.otherUser.photoThumbnailURL
                            )
                            if isLoading {
                                ProgressView()
                                    .tint(NADATheme.brandPressed)
                                    .padding(.top, 8)
                            } else {
                                Text("Couldn't load this profile.")
                                    .font(NADATheme.bodyFont)
                                    .foregroundStyle(NADATheme.secondaryInk)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 108)
                    }
                }
            }

            floatingActions
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.otherUser.displayName)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(NADATheme.ink)
                    .lineLimit(1)
                ProfileZodiacCaption(sign: candidate?.zodiac)
            }
            Spacer(minLength: 10)
            Button(action: onAll) {
                HStack(spacing: 5) {
                    Image(systemName: "person.2")
                        .font(.system(size: 12, weight: .semibold))
                    Text("All")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NADATheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(NADATheme.hairline.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All clicks")
            .accessibilityHint("Returns to everyone who clicked you")
        }
    }

    private func profileScroll(_ candidate: DiscoverCandidate) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                likeContextCard

                DiscoverCandidateStack(
                    candidate: candidate,
                    catalogInterests: catalogInterests,
                    viewerInterestIds: viewerInterestIds,
                    showsName: false
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 108)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var likeContextCard: some View {
        let comment = item.like.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasComment = comment?.isEmpty == false
        let hasTarget = item.target.type != .profile

        if hasComment || hasTarget {
            VStack(alignment: .leading, spacing: 12) {
                if hasTarget {
                    LikeInboxTargetPreview(target: item.target)
                }
                if let comment, hasComment {
                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(NADATheme.brand.opacity(0.55))
                            .frame(width: 3)
                        Text(comment)
                            .font(.system(size: 16))
                            .foregroundStyle(NADATheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            }
        }
    }

    private var floatingActions: some View {
        HStack {
            Button(action: onPass) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(NADATheme.brand)
                    .frame(width: 64, height: 64)
                    .background(NADATheme.paper, in: Circle())
                    .shadow(color: NADATheme.ink.opacity(0.12), radius: 10, y: 3)
            }
            .disabled(isPending)
            .accessibilityLabel("Pass")

            Spacer()

            Button(action: onLikeBack) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NADATheme.paper)
                    .frame(width: 64, height: 64)
                    .background(NADATheme.brand, in: Circle())
                    .shadow(
                        color: NADATheme.brand.opacity(isGlowing ? 0.55 : 0.28),
                        radius: isGlowing ? 18 : 12,
                        y: 4
                    )
                    .scaleEffect(isGlowing ? 1.08 : 1)
            }
            .buttonStyle(NADATactilePressStyle())
            .disabled(isPending)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isGlowing)
            .accessibilityLabel("Click back")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
        .opacity(isPending && !isGlowing ? 0.6 : 1)
        .allowsHitTesting(!isPending)
    }
}

private struct LikeInboxTargetPreview: View {
    let target: LikeTargetPreview

    var body: some View {
        switch target.type {
        case .profile:
            EmptyView()
        case .photo:
            if let url = target.photoURL ?? target.photoThumbnailURL {
                RemoteImageView(
                    urlString: url,
                    thumbnailURLString: target.photoThumbnailURL,
                    targetPointSize: RemoteImageView.thumbnailPointSize
                )
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .prompt:
            if let answer = target.answerText, !answer.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if let prompt = target.promptText, !prompt.isEmpty {
                        Text(prompt)
                            .font(.system(size: 13))
                            .foregroundStyle(NADATheme.brandPressed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(answer)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NADATheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NADATheme.brandSoft.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

#Preview {
    LikesInboxView()
        .environment(AuthManager())
}
