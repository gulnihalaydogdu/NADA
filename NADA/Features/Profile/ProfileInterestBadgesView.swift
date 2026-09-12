import SwiftUI

/// Wrapping chip row — used by the Interests editor and Preview badges.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }

        let height = y + lineHeight
        return (CGSize(width: width, height: height), positions, sizes)
    }
}

struct InterestBadgeChip: View {
    let label: String
    var isSelected = false
    var isInteractive = false

    var body: some View {
        HStack(spacing: 6) {
            if isSelected, isInteractive {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(chipForeground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(chipStroke, lineWidth: 0.8)
        )
    }

    private var chipForeground: Color {
        if isInteractive {
            return isSelected ? NADATheme.brandPressed : NADATheme.ink
        }
        return isSelected ? NADATheme.onBrand : NADATheme.ink
    }

    private var chipBackground: Color {
        if isInteractive {
            return isSelected ? NADATheme.brandSoft : NADATheme.card
        }
        return isSelected ? NADATheme.brand : NADATheme.card
    }

    private var chipStroke: Color {
        if isInteractive {
            return isSelected ? NADATheme.brand.opacity(0.55) : NADATheme.ink.opacity(0.1)
        }
        return isSelected ? Color.clear : NADATheme.ink.opacity(0.1)
    }
}

/// Read-only wrap of selected badges — Preview / Discover card.
struct ProfileInterestBadgesView: View {
    let interests: [Interest]
    var title: String = "Interests"
    var emphasized = true

    var body: some View {
        if interests.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NADATheme.ink)

                InterestBadgeWrap(interests: interests, allEmphasized: emphasized)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            )
        }
    }
}

/// Discover: one Interests card. Shared badges are coral; the rest stay outlined.
struct DiscoverInterestOverlapView: View {
    let interests: [Interest]
    let viewerInterestIds: [String]

    private var sharedIds: Set<String> { Set(viewerInterestIds) }

    var body: some View {
        if interests.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Interests")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NADATheme.ink)

                InterestBadgeWrap(interests: interests, selectedIds: sharedIds)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            )
        }
    }
}

private struct InterestBadgeWrap: View {
    let interests: [Interest]
    var selectedIds: Set<String> = []
    var allEmphasized = false

    var body: some View {
        WrappingHStack(spacing: 7, lineSpacing: 7) {
            ForEach(interests) { interest in
                InterestBadgeChip(
                    label: interest.label,
                    isSelected: allEmphasized || selectedIds.contains(interest.id)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
