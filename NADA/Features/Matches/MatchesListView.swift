import SwiftUI

/// Mutuals list (W4-02). Chat unlock is Week 5.
struct MatchesListView: View {
    @Environment(AuthManager.self) private var auth

    @State private var items: [MatchListItem] = []
    @State private var cursor: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isPaging = false
    @State private var localError: String?

    var body: some View {
        ZStack {
            NADAScreenBackground(showBottomBlob: false)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if let message = localError {
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
        .task(id: auth.currentUser?.id) {
            await loadInitial()
        }
        .onAppear {
            guard hasLoaded else { return }
            Task { await reload() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mutuals")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)
            Spacer()
            if !items.isEmpty {
                Text(items.count == 1 ? "1 mutual" : "\(items.count) mutuals")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, items.isEmpty {
            Spacer()
            ProgressView()
                .tint(NADATheme.brandPressed)
            Spacer()
        } else if items.isEmpty, hasLoaded {
            emptyState
        } else if items.isEmpty {
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        MatchesListRow(item: item)
                    }

                    if cursor != nil {
                        ProgressView()
                            .tint(NADATheme.brandPressed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .task(id: cursor) {
                                await loadMore()
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .refreshable {
                await reload()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .padding(20)
                .background(NADATheme.brandSoft, in: Circle())

            Text("No mutuals yet")
                .font(NADATheme.displayFont)
                .foregroundStyle(NADATheme.ink)

            Text("When you click someone back, they land here — not in Clicks.")
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

    private func loadInitial() async {
        guard auth.currentUser != nil else { return }
        if hasLoaded {
            await reload()
            return
        }
        guard !isLoading else { return }
        isLoading = true
        await reload()
    }

    private func reload() async {
        guard auth.currentUser != nil else { return }
        localError = nil
        do {
            let page = try await auth.fetchMatches()
            items = page.items
            cursor = page.cursor
            localError = nil
        } catch {
            localError = AuthManager.matchesListErrorMessage(error)
        }
        hasLoaded = true
        isLoading = false
        isPaging = false
        prefetchAvatars(items)
    }

    private func loadMore() async {
        guard let cursor, !isPaging else { return }
        isPaging = true
        do {
            let page = try await auth.fetchMatches(cursor: cursor)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            self.cursor = page.cursor
            localError = nil
        } catch {
            localError = AuthManager.matchesListErrorMessage(error)
        }
        isPaging = false
        prefetchAvatars(items)
    }

    private func prefetchAvatars(_ items: [MatchListItem]) {
        let size = RemoteImageView.thumbnailPointSize
        let ordered = items.prefix(8).compactMap { item -> (urlString: String, targetPointSize: CGFloat)? in
            guard let url = item.otherUser.photoThumbnailURL ?? item.otherUser.photoURL else { return nil }
            return (url, size)
        }
        RemoteImageLoader.shared.prefetchOrdered(Array(ordered))
    }
}

private struct MatchesListRow: View {
    let item: MatchListItem

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
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
                            .foregroundStyle(NADATheme.brand)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.otherUser.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NADATheme.ink)
                    .lineLimit(1)
                Text("You're mutuals")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
            }

            Spacer(minLength: 8)

            if let date = item.match.createdAt {
                Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)
            }
        }
        .padding(16)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NADATheme.hairline.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: NADATheme.ink.opacity(0.05), radius: 8, y: 4)
    }
}
