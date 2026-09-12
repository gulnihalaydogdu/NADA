import SwiftUI

/// One-to-one text thread for a mutual (W5-06). Opening Say hi / click notes seed as first bubbles.
struct ChatThreadView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let item: MatchListItem

    @State private var liveMessages: [ChatMessage] = []
    @State private var olderMessages: [ChatMessage] = []
    @State private var olderCursor: String?
    @State private var isLoadingOlder = false
    @State private var draft = ""
    @State private var localError: String?
    @State private var isSending = false
    @State private var stopListening: (() -> Void)?
    @FocusState private var composerFocused: Bool

    private var viewerId: String? { auth.currentUser?.id }

    private var messages: [ChatMessage] {
        let liveIds = Set(liveMessages.map(\.id))
        return (olderMessages.filter { !liveIds.contains($0.id) } + liveMessages)
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending
            && !trimmedDraft.isEmpty
            && trimmedDraft.count <= ChatMessage.maxTextLength
            && item.match.isActive
    }

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                if let localError {
                    Text(localError)
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                messageList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startListening()
        }
        .task(id: item.match.id) {
            await auth.seedOpeningChatMessages(
                matchId: item.match.id,
                otherUserId: item.otherUser.id
            )
        }
        .onDisappear {
            stopListening?()
            stopListening = nil
        }
        .task(id: messages.map(\.id).joined()) {
            await auth.markChatRead(matchId: item.match.id, messages: messages)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            NADABackButton { dismiss() }

            avatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.otherUser.displayName)
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
                    .lineLimit(1)
                Text("Mutuals")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if olderCursor != nil {
                        ProgressView()
                            .tint(NADATheme.brandPressed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .task {
                                await loadOlder()
                            }
                    }

                    if messages.isEmpty {
                        emptyState
                            .padding(.top, 48)
                    } else {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.always)
            .onChange(of: messages.last?.id) { _, newId in
                guard let newId else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(18)
                .background(NADATheme.brandSoft, in: Circle())

            Text("Say hi")
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)

            Text("Hangouts start with a hello — coffee, a walk, whatever fits.")
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderId == viewerId
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            Text(message.body)
                .font(NADATheme.bodyFont)
                .foregroundStyle(isMine ? NADATheme.onBrand : NADATheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isMine ? NADATheme.brand : NADATheme.card,
                    in: UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 18,
                            bottomLeading: isMine ? 18 : 6,
                            bottomTrailing: isMine ? 6 : 18,
                            topTrailing: 18
                        ),
                        style: .continuous
                    )
                )
                .overlay {
                    if !isMine {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 18,
                                bottomLeading: 6,
                                bottomTrailing: 18,
                                topTrailing: 18
                            ),
                            style: .continuous
                        )
                        .strokeBorder(NADATheme.hairline.opacity(0.7), lineWidth: 1)
                    }
                }

            HStack(spacing: 6) {
                if let date = message.createdAt {
                    Text(Self.timeFormatter.string(from: date))
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                }
                if isMine, isLastOwnMessage(message), message.isRead {
                    Text("Seen")
                        .font(NADATheme.captionFont)
                        .foregroundStyle(NADATheme.brandPressed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.leading, isMine ? 56 : 0)
        .padding(.trailing, isMine ? 0 : 56)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !item.match.isActive {
                Text("This chat is closed.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message \(item.otherUser.displayName)…", text: $draft, axis: .vertical)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.ink)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        NADATheme.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NADATheme.onBrand)
                        .frame(width: 36, height: 36)
                        .background(
                            canSend ? NADATheme.brand : NADATheme.brand.opacity(0.4),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(NADATheme.paper.ignoresSafeArea(edges: .bottom))
    }

    private var avatar: some View {
        Group {
            if item.otherUser.photoURL?.isEmpty == false
                || item.otherUser.photoThumbnailURL?.isEmpty == false {
                RemoteImageView(
                    urlString: item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL,
                    thumbnailURLString: item.otherUser.photoThumbnailURL,
                    targetPointSize: RemoteImageView.thumbnailPointSize
                )
            } else {
                ZStack {
                    NADATheme.brandSoft
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(NADATheme.brand)
                }
            }
        }
    }

    private func isLastOwnMessage(_ message: ChatMessage) -> Bool {
        messages.last(where: { $0.senderId == viewerId })?.id == message.id
    }

    private func startListening() {
        stopListening?()
        stopListening = auth.listenChatMessages(matchId: item.match.id) { latest in
            applyLive(latest)
            localError = nil
        }
        Task {
            do {
                let page = try await auth.fetchChatMessages(matchId: item.match.id)
                applyLive(page.messages)
                olderCursor = page.cursor
            } catch {
                localError = AuthManager.chatErrorMessage(error)
            }
        }
    }

    /// Keep a just-sent bubble if the ordered listener hasn't picked it up yet.
    private func applyLive(_ latest: [ChatMessage]) {
        let latestIds = Set(latest.map(\.id))
        let pending = liveMessages.filter { !latestIds.contains($0.id) }
        liveMessages = (latest + pending)
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private func loadOlder() async {
        guard let olderCursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        do {
            let page = try await auth.fetchChatMessages(matchId: item.match.id, cursor: olderCursor)
            let known = Set(messages.map(\.id))
            olderMessages = page.messages.filter { !known.contains($0.id) } + olderMessages
            self.olderCursor = page.cursor
        } catch {
            localError = AuthManager.chatErrorMessage(error)
        }
        isLoadingOlder = false
    }

    private func send() async {
        guard canSend else { return }
        let text = trimmedDraft
        isSending = true
        localError = nil
        draft = ""
        composerFocused = true
        if let sent = await auth.sendChatMessage(matchId: item.match.id, body: text) {
            applyLive([sent])
        } else {
            draft = text
            localError = auth.errorMessage ?? "Couldn't send that. Try again."
        }
        isSending = false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
