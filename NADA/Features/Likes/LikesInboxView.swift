import SwiftUI

/// Likes inbox (W4-05 / W4-06) — who liked you and what you sent, with the liked
/// photo / Bit and the comment. Rows decode at thumbnail size so the list scrolls
/// without the 430pt Discover decode.
struct LikesInboxView: View {
    @Environment(AuthManager.self) private var auth

    @State private var direction: LikeInboxDirection = .incoming
    @State private var incoming = InboxSection()
    @State private var sent = InboxSection()
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
        let userId: String
        let displayName: String
        let glowLikeId: String
        let targetType: DiscoverLike.TargetType
        let targetId: String
        let title: String

        var id: String { "\(userId)|\(targetType.rawValue)|\(targetId)" }
    }

    private struct InboxSection {
        var items: [InboxLike] = []
        var cursor: String?
        var hasLoaded = false
        var isLoading = false
        var isPaging = false
    }

    private var section: InboxSection {
        direction == .incoming ? incoming : sent
    }

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            VStack(spacing: 0) {
                if let openedItem {
                    LikeInboxProfileView(
                        item: openedItem,
                        direction: direction,
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

                    LikeInboxSwitcher(
                        selection: $direction,
                        incomingCount: auth.incomingLikerCount
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
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
        }
        .task(id: loadToken) {
            Task {
                catalogInterests = (try? await FirestoreInterestService().fetchActiveInterests()) ?? catalogInterests
            }
            await loadInitial()
        }
        .sheet(item: $likeBackDraft) { draft in
            DiscoverLikeCommentSheet(
                title: draft.displayName,
                subtitle: "Say hi before you match — optional, hangout vibes only.",
                placeholder: "Write a short note…",
                sendTitle: "Like back",
                navigationTitle: "Like back",
                isBusy: isSendingLikeBack
            ) { comment in
                Task {
                    await sendLikeBack(draft: draft, comment: comment)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isSendingLikeBack)
        }
    }

    private var loadToken: String {
        "\(auth.currentUser?.id ?? "")|\(direction.rawValue)"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Likes")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
            Spacer()
            if direction == .incoming, auth.incomingLikerCount > 0 {
                Text(auth.incomingLikerCount == 1 ? "1 new like" : "\(auth.incomingLikerCount) new likes")
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
                            direction: direction,
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
            Image(systemName: direction == .incoming ? "heart" : "paperplane")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(20)
                .background(NADATheme.brandSoft, in: Circle())

            Text(direction == .incoming ? "No likes yet" : "Nothing sent yet")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)

            Text(
                direction == .incoming
                    ? "When someone likes your photo, a Bit, or your whole profile, it lands right here."
                    : "Likes you send from Discover show up here while you wait to hear back."
            )
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
        if let cached = auth.cachedLikeInbox(direction: direction), !cached.items.isEmpty {
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
        direction == .incoming
            ? await auth.fetchIncomingLikes(cursor: cursor)
            : await auth.fetchSentLikes(cursor: cursor)
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
        if direction == .incoming {
            incoming = state
        } else {
            sent = state
        }
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

    private func presentLikeBack(
        _ item: InboxLike,
        targetType: DiscoverLike.TargetType = .profile,
        targetId: String? = nil,
        title: String? = nil
    ) {
        let userId = item.otherUser.id
        guard !pendingUserIds.contains(userId) else { return }
        likeBackDraft = LikeBackDraft(
            userId: userId,
            displayName: item.otherUser.displayName,
            glowLikeId: item.id,
            targetType: targetType,
            targetId: targetId ?? userId,
            title: title ?? item.otherUser.displayName
        )
    }

    private func sendLikeBack(draft: LikeBackDraft, comment: String?) async {
        guard !pendingUserIds.contains(draft.userId), !isSendingLikeBack else { return }
        pendingUserIds.insert(draft.userId)
        isSendingLikeBack = true
        localError = nil
        likeBackDraft = nil
        isSendingLikeBack = false
        let removed = removeRows(userId: draft.userId)
        closeProfile()

        let created = await auth.likeDiscoverTarget(
            toUserId: draft.userId,
            targetType: draft.targetType,
            targetId: draft.targetId,
            comment: comment
        )
        pendingUserIds.remove(draft.userId)

        guard created != nil else {
            restoreRows(removed)
            if auth.errorMessage == nil {
                localError = "Couldn't send that like. Try again."
            }
            return
        }
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
                    localError = "Couldn't pass on that like. Try again."
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

// MARK: - Switcher

private struct LikeInboxSwitcher: View {
    @Binding var selection: LikeInboxDirection
    let incomingCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LikeInboxDirection.allCases) { option in
                let isSelected = option == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                        if option == .incoming, incomingCount > 0 {
                            Text("\(incomingCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isSelected ? NADATheme.onBrand : NADATheme.brandPressed)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    isSelected ? NADATheme.onBrand.opacity(0.28) : NADATheme.brandSoft,
                                    in: Capsule()
                                )
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? NADATheme.onBrand : NADATheme.warmSecondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            Capsule().fill(NADATheme.brand)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(NADATheme.surface.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(NADATheme.hairline.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Row

private struct LikeInboxRow: View {
    let item: InboxLike
    let direction: LikeInboxDirection
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

                    if direction == .sent {
                        sentStatus
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile")

            if direction == .incoming {
                actions
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 14)
            }
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
        return direction == .incoming ? "liked your \(thing)" : "you liked their \(thing)"
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
                    Text("Like back")
                }
            }
            .buttonStyle(LikeInboxCapsuleStyle(kind: .brand))
            .disabled(isPending)
        }
        .opacity(isPending && !isGlowing ? 0.6 : 1)
    }

    private var sentStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
            Text("Waiting to hear back")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(NADATheme.warmSecondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(NADATheme.surface.opacity(0.9), in: Capsule())
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
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Profile (Hinge-style)

private struct LikeInboxProfileView: View {
    let item: InboxLike
    let direction: LikeInboxDirection
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
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                if let candidate {
                    profileScroll(candidate)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
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
                        .padding(.bottom, direction == .incoming ? 108 : 24)
                    }
                }
            }

            if direction == .incoming {
                floatingActions
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.otherUser.displayName)
                    .font(NADATheme.displayFont)
                    .foregroundStyle(NADATheme.ink)
                    .lineLimit(1)
                Text(contextSubtitle)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("All", action: onAll)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NADATheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NADATheme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(NADATheme.hairline, lineWidth: 1))
                .shadow(color: NADATheme.ink.opacity(0.05), radius: 6, y: 2)
                .accessibilityLabel("All likes")
        }
    }

    private var contextSubtitle: String {
        let thing: String
        switch item.target.type {
        case .photo: thing = "photo"
        case .prompt: thing = "Bit"
        case .profile: thing = "profile"
        }
        return direction == .incoming ? "liked your \(thing)" : "you liked their \(thing)"
    }

    private func profileScroll(_ candidate: DiscoverCandidate) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    likeContextCard

                    DiscoverCandidateStack(
                        candidate: candidate,
                        catalogInterests: catalogInterests,
                        viewerInterestIds: viewerInterestIds,
                        highlightedPhotoId: direction == .sent && item.target.type == .photo
                            ? item.target.targetId : nil,
                        highlightedPromptId: direction == .sent && item.target.type == .prompt
                            ? item.target.targetId : nil,
                        highlightLabel: direction == .sent ? "You liked this" : nil,
                        showsName: false
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, direction == .incoming ? 108 : 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                scrollToLikedTarget(proxy)
            }
            .onChange(of: candidate.id) { _, _ in
                scrollToLikedTarget(proxy)
            }
        }
    }

    private func scrollToLikedTarget(_ proxy: ScrollViewProxy) {
        guard direction == .sent else { return }
        switch item.target.type {
        case .photo:
            proxy.scrollTo("photo-\(item.target.targetId)", anchor: .top)
        case .prompt:
            proxy.scrollTo("prompt-\(item.target.targetId)", anchor: .top)
        case .profile:
            break
        }
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
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.7), lineWidth: 1)
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
                    .shadow(color: NADATheme.ink.opacity(0.16), radius: 12, y: 4)
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
            .disabled(isPending)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isGlowing)
            .accessibilityLabel("Like back")
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
