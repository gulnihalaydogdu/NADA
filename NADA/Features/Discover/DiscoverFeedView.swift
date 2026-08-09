import SwiftUI

/// One-at-a-time Discover feed (W3-06) — loads candidates from W3-01.
struct DiscoverFeedView: View {
    @Environment(AuthManager.self) private var auth

    @State private var queue: [DiscoverCandidate] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var localError: String?
    @State private var scrollToTopToken = 0

    private var current: DiscoverCandidate? { queue.first }

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

                        DiscoverCandidateStack(candidate: current)
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

                nextBar
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

    private var nextBar: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Next profile")
                }
            }
            .buttonStyle(NADAPrimaryButtonStyle())
            .disabled(isLoading)

            Text("Like & skip come next — for now, browse who’s nearby.")
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

    private func advance() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
        scrollToTopToken += 1
        prefetchUpcomingPhotos()
        if queue.count <= 2 {
            Task { await loadMoreIfNeeded() }
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

    /// Warm the next profiles' photo URLs so Next feels snappier.
    private func prefetchUpcomingPhotos() {
        let urls = queue.prefix(3).flatMap { candidate in
            candidate.photos.prefix(2).map(\.url)
        }
        ImagePrefetcher.prefetch(urlStrings: Array(urls))
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

    var body: some View {
        Group {
            if isPrimaryReady {
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
            isPrimaryReady = false
            await warmPrimaryPhoto()
            // Prefetch the rest of this card in the background.
            ImagePrefetcher.prefetch(urlStrings: candidate.photos.dropFirst().map(\.url))
            isPrimaryReady = true
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
                ProfilePreviewBitCard(prompt: firstBit.promptText, answer: firstBit.answerText)
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
                    ProfilePreviewBitCard(prompt: bit.promptText, answer: bit.answerText)
                }
            }
        }
    }

    private func warmPrimaryPhoto() async {
        guard let urlString = candidate.primaryPhotoURL ?? candidate.photos.first?.url,
              let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        _ = try? await URLSession.shared.data(for: request)
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

#Preview {
    DiscoverFeedView()
        .environment(AuthManager())
}
