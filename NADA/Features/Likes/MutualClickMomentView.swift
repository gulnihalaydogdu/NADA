import SwiftUI

/// Tiny confirmation when a click is mutual — not a match splash.
struct MutualClickSnapshot: Equatable {
    let viewerURL: String?
    let viewerThumb: String?
    let otherURL: String?
    let otherThumb: String?
}

struct MutualClickMomentView: View {
    let snapshot: MutualClickSnapshot

    @State private var gathered = false
    @State private var ring: CGFloat = 0
    @State private var titleVisible = false
    @State private var subtitleVisible = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                expandingRing
                    .frame(width: 40, height: 40)

                HStack(spacing: gathered ? -8 : 12) {
                    momentAvatar(url: snapshot.viewerURL, thumb: snapshot.viewerThumb)
                        .zIndex(0)
                    momentAvatar(url: snapshot.otherURL, thumb: snapshot.otherThumb)
                        .zIndex(1)
                }
                .scaleEffect(gathered ? 1 : 0.97)
            }
            .frame(height: 52)

            VStack(spacing: 3) {
                Text("It’s mutual.")
                    .font(NADATheme.headlineFont)
                    .foregroundStyle(NADATheme.ink)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 6)

                Text("You can chat now.")
                    .font(NADATheme.captionFont)
                    .foregroundStyle(NADATheme.warmSecondaryInk)
                    .opacity(subtitleVisible ? 1 : 0)
                    .offset(y: subtitleVisible ? 0 : 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(NADATheme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(NADATheme.hairline.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: NADATheme.ink.opacity(0.08), radius: 16, y: 6)
        .onAppear(perform: play)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.42), trigger: titleVisible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("It’s mutual. You can chat now.")
    }

    private var expandingRing: some View {
        Circle()
            .stroke(NADATheme.brand.opacity(0.4), lineWidth: 1)
            .scaleEffect(0.5 + ring * 0.85)
            .opacity(ring > 0 ? Double((1 - ring) * 0.65) : 0)
            .allowsHitTesting(false)
    }

    private func momentAvatar(url: String?, thumb: String?) -> some View {
        Group {
            if let shown = thumb ?? url, !shown.isEmpty {
                RemoteImageView(
                    urlString: shown,
                    thumbnailURLString: thumb,
                    targetPointSize: RemoteImageView.thumbnailPointSize
                )
            } else {
                ZStack {
                    NADATheme.brandSoft
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NADATheme.brand)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(NADATheme.card, lineWidth: 2))
    }

    private func play() {
        withAnimation(.easeOut(duration: 0.32)) {
            gathered = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.06)) {
            ring = 1
        }
        withAnimation(.easeOut(duration: 0.26).delay(0.14)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.26).delay(0.26)) {
            subtitleVisible = true
        }
    }
}

/// Press: ~90ms settle in, soft spring back. Not bouncy.
struct NADATactilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.09)
                    : .spring(response: 0.22, dampingFraction: 0.86),
                value: configuration.isPressed
            )
    }
}

#Preview {
    ZStack {
        NADATheme.paper.ignoresSafeArea()
        MutualClickMomentView(
            snapshot: MutualClickSnapshot(
                viewerURL: nil,
                viewerThumb: nil,
                otherURL: nil,
                otherThumb: nil
            )
        )
    }
}
