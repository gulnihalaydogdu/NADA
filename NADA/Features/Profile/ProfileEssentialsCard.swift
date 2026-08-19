import SwiftUI

/// Quick facts + background rows for Discover / Preview / inbox profile.
struct ProfileEssentialsCard: View {
    struct Model: Equatable {
        var age: Int?
        var gender: String?
        var city: String?
        var jobTitle: String?
        var university: String?
        var hangoutLookingFor: String?
        var openToGroups: Bool?
    }

    let model: Model

    var isEmpty: Bool {
        topItems.isEmpty && !hasDetailRows
    }

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                if !topItems.isEmpty {
                    topRow
                }
                if hasDetailRows {
                    if !topItems.isEmpty { divider }
                    detailList
                }
            }
            .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NADATheme.hairline.opacity(0.38), lineWidth: 1)
            )
        }
    }

    private var topItems: [(systemImage: String, text: String)] {
        var items: [(String, String)] = []
        if let age = model.age {
            items.append(("birthday.cake", String(age)))
        }
        if let gender = model.gender, !gender.isEmpty {
            items.append(("person", gender))
        }
        if let city = model.city, !city.isEmpty {
            items.append(("mappin.and.ellipse", city))
        }
        return items
    }

    private var hasDetailRows: Bool {
        !(model.jobTitle ?? "").isEmpty
            || !(model.university ?? "").isEmpty
            || !(model.hangoutLookingFor ?? "").isEmpty
            || model.openToGroups == true
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(topItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { verticalRule }
                topCell(systemImage: item.systemImage, text: item.text)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(NADATheme.ink.opacity(0.1))
            .frame(width: 1, height: 28)
    }

    private func topCell(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NADATheme.brandPressed)
            Text(text)
                .font(NADATheme.headlineFont)
                .foregroundStyle(NADATheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(NADATheme.ink.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private var detailList: some View {
        let rows = detailRows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                detailRow(
                    systemImage: row.systemImage,
                    text: row.text,
                    showDivider: index > 0
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var detailRows: [(systemImage: String, text: String)] {
        var rows: [(String, String)] = []
        if let job = model.jobTitle, !job.isEmpty {
            rows.append(("briefcase", job))
        }
        if let university = model.university, !university.isEmpty {
            rows.append(("graduationcap", university))
        }
        if let lookingFor = model.hangoutLookingFor, !lookingFor.isEmpty {
            rows.append(("magnifyingglass", lookingFor))
        }
        if model.openToGroups == true {
            rows.append(("person.2", "Open to including friends in groups"))
        }
        return rows
    }

    private func detailRow(
        systemImage: String,
        text: String,
        showDivider: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            if showDivider {
                Rectangle()
                    .fill(NADATheme.ink.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NADATheme.brandPressed)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 1)

                Text(text)
                    .font(NADATheme.bodyFont)
                    .foregroundStyle(NADATheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}

/// Sign + name under a display name. Coral, not in the essentials card.
struct ProfileZodiacCaption: View {
    let sign: ZodiacSign?

    var body: some View {
        if let sign {
            HStack(spacing: 5) {
                Text(sign.glyph)
                Text(sign.title)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(NADATheme.brand)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sign.title)
        }
    }
}

#Preview("Essentials card") {
    ProfileEssentialsCard(
        model: .init(
            age: 22,
            gender: "Woman",
            city: "Ankara",
            jobTitle: "Singer",
            university: "Istanbul Technical University",
            hangoutLookingFor: "Looking for Guno",
            openToGroups: nil
        )
    )
    .padding(24)
    .background(NADATheme.paper)
}
