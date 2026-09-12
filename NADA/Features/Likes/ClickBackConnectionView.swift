import SwiftUI

/// Click-back screen from Clicks — full page, not a bottom sheet.
struct ClickBackConnectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let name: String
    let target: LikeTargetPreview
    let incomingComment: String?
    let otherPhotoURL: String?
    let otherPhotoThumbnailURL: String?
    var isBusy = false
    let onSend: (String?) -> Void
    let onDismiss: () -> Void

    @State private var message = ""
    @FocusState private var messageFocused: Bool
    @State private var isVisible = false
    @State private var isExiting = false
    @State private var dragOffset: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    private var firstName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        trimmed.count <= DiscoverLike.maxCommentLength && !isBusy
    }

    private var contextLine: String {
        switch target.type {
        case .photo: return "Clicked your photo"
        case .prompt: return "Clicked your Bit"
        case .profile: return "Clicked your profile"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            NavigationStack {
                ZStack {
                    NADATheme.paper.ignoresSafeArea()

                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ScrollView {
                            VStack(spacing: 18) {
                                VStack(spacing: 8) {
                                    Text("New connection")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(NADATheme.brand)

                                    Text(name)
                                        .font(NADATheme.displayFont)
                                        .foregroundStyle(NADATheme.ink)
                                        .multilineTextAlignment(.center)

                                    Text(contextLine)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(NADATheme.brand)

                                    if let incomingComment, !incomingComment.isEmpty {
                                        Text(incomingComment)
                                            .font(NADATheme.bodyFont)
                                            .foregroundStyle(NADATheme.secondaryInk)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 12)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                featuredContent

                                messageField

                                Button {
                                    send()
                                } label: {
                                    if isBusy {
                                        ProgressView()
                                            .tint(NADATheme.onBrand)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("Say hi to \(firstName)")
                                    }
                                }
                                .nadaPrimaryCTA(enabled: canSend && !isExiting)

                                Button("Not now") { dismissAnimated() }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(NADATheme.secondaryInk)
                                    .padding(.top, 2)
                                    .disabled(isBusy || isExiting)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 28)
                        }
                        .scrollDismissesKeyboard(.immediately)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { messageFocused = false }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NADATheme.brand)
                    }
                }
            }
            .compositingGroup()
            .opacity(surfaceOpacity)
            .offset(y: surfaceOffset)
            .scaleEffect(surfaceScale)
            .onAppear {
                containerHeight = height
                guard !isVisible, !isExiting else { return }
                withAnimation(appearAnimation) {
                    isVisible = true
                }
            }
            .onChange(of: height) { _, newHeight in
                containerHeight = newHeight
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var header: some View {
        HStack {
            Button(action: dismissAnimated) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NADATheme.ink)
                    .frame(width: 36, height: 36)
            }
            .disabled(isBusy || isExiting)
            .accessibilityLabel("Close")
            Spacer()
        }
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    @ViewBuilder
    private var featuredContent: some View {
        switch target.type {
        case .photo:
            photoFeature(
                url: target.photoURL ?? otherPhotoURL,
                thumb: target.photoThumbnailURL ?? otherPhotoThumbnailURL,
                bubble: "They clicked this photo of you"
            )
        case .prompt:
            if let answer = target.answerText, !answer.isEmpty {
                ProfilePreviewBitCard(prompt: target.promptText ?? "", answer: answer)
            } else {
                photoFeature(url: otherPhotoURL, thumb: otherPhotoThumbnailURL, bubble: nil)
            }
        case .profile:
            photoFeature(url: otherPhotoURL, thumb: otherPhotoThumbnailURL, bubble: nil)
        }
    }

    private func photoFeature(url: String?, thumb: String?, bubble: String?) -> some View {
        ProfilePreviewPhotoTile(urlString: url, thumbnailURLString: thumb)
            .overlay(alignment: .bottomLeading) {
                if let bubble {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NADATheme.brand)
                        Text(bubble)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NADATheme.ink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NADATheme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: NADATheme.ink.opacity(0.08), radius: 8, y: 2)
                    .padding(12)
                }
            }
    }

    private var messageField: some View {
        HStack(spacing: 10) {
            Image(systemName: "face.smiling")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(NADATheme.secondaryInk)

            TextField("Write a message...", text: $message, axis: .vertical)
                .font(NADATheme.bodyFont)
                .foregroundStyle(NADATheme.ink)
                .lineLimit(1...3)
                .focused($messageFocused)
                .submitLabel(.done)
                .onSubmit { messageFocused = false }

            Button(action: send) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NADATheme.onBrand)
                    .frame(width: 32, height: 32)
                    .background(NADATheme.brand, in: Circle())
            }
            .disabled(!canSend || isExiting)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(NADATheme.hairline.opacity(0.7), lineWidth: 1)
        }
    }

    private func send() {
        guard canSend, !isExiting else { return }
        let comment = trimmed.isEmpty ? nil : String(trimmed.prefix(DiscoverLike.maxCommentLength))
        exit {
            onSend(comment)
        }
    }

    private func dismissAnimated() {
        guard !isExiting, !isBusy else { return }
        exit(onDismiss)
    }

    private var appearAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.48, dampingFraction: 0.92)
    }

    private var dismissAnimation: Animation {
        reduceMotion
            ? .easeIn(duration: 0.16)
            : .spring(response: 0.36, dampingFraction: 0.94)
    }

    private var dragProgress: CGFloat {
        let height = max(containerHeight, 1)
        return min(1, max(0, dragOffset / (height * 0.42)))
    }

    private var surfaceOpacity: Double {
        let base: Double = isVisible ? 1 : 0
        return base * Double(1 - dragProgress * 0.28)
    }

    private var surfaceOffset: CGFloat {
        let rest: CGFloat = isVisible ? 0 : (reduceMotion ? 0 : 22)
        return rest + dragOffset
    }

    private var surfaceScale: CGFloat {
        if reduceMotion { return 1 }
        let rest: CGFloat = isVisible ? 1 : 0.975
        return rest - dragProgress * 0.015
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isExiting, !isBusy else { return }
                if messageFocused { messageFocused = false }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isExiting, !isBusy else { return }
                let height = max(containerHeight, 1)
                let shouldDismiss = value.translation.height > height * 0.18
                    || value.predictedEndTranslation.height > height * 0.4
                if shouldDismiss {
                    exit(onDismiss)
                } else {
                    withAnimation(dismissAnimation) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func exit(_ finish: @escaping () -> Void) {
        isExiting = true
        messageFocused = false
        withAnimation(dismissAnimation) {
            isVisible = false
            dragOffset = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 180_000_000 : 380_000_000)
            finish()
        }
    }
}
