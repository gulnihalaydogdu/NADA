import SwiftUI

/// Optional note on a like — used from Discover and from Like back in the inbox.
struct DiscoverLikeCommentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var subtitle: String = "Add a short note (optional) — hangout vibes only."
    var placeholder: String = "Say why you’re down to hang…"
    var sendTitle: String = "Send like"
    var navigationTitle: String = "Like"
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

                Text(subtitle)
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.secondaryInk)

                TextField(placeholder, text: $comment, axis: .vertical)
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
                        Text(sendTitle)
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
