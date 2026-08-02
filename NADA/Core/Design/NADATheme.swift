import SwiftUI

enum NADATheme {
    // NADA Coral palette (§12) — light mode only for MVP
    static let paper = Color(red: 0.980, green: 0.973, blue: 0.965)       // #FAF8F6 warm paper
    static let surface = Color(red: 0.961, green: 0.929, blue: 0.910)     // #F5EDE8
    static let ink = Color(red: 0.102, green: 0.086, blue: 0.145)         // #1A1625
    static let secondaryInk = Color(red: 0.435, green: 0.408, blue: 0.478) // #6F687A
    static let warmSecondaryInk = Color(red: 0.361, green: 0.337, blue: 0.408) // #5C5668
    static let brand = Color(red: 0.757, green: 0.482, blue: 0.435)         // #C17B6F dusty coral
    static let brandPressed = Color(red: 0.647, green: 0.392, blue: 0.345)  // #A56458
    static let brandSoft = Color(red: 0.961, green: 0.910, blue: 0.890)    // #F5E8E3 blush wash
    static let onBrand = Color(red: 0.980, green: 0.973, blue: 0.965)       // light on coral CTA
    static let danger = Color(red: 0.706, green: 0.137, blue: 0.094)       // #B42318
    static let hairline = Color(red: 0.898, green: 0.835, blue: 0.812)    // #E5D5CF
    static let card = Color(red: 0.996, green: 0.992, blue: 0.988)         // #FEFDFC card on paper

    static let titleFont = Font.system(.title, design: .default, weight: .bold)
    static let displayFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(.headline, design: .default, weight: .semibold)
    static let bodyFont = Font.system(.body, design: .default)
    static let captionFont = Font.system(.caption, design: .default)
}

struct NADAPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.onBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(configuration.isPressed ? NADATheme.brandPressed : NADATheme.brand)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: NADATheme.brand.opacity(configuration.isPressed ? 0.1 : 0.2), radius: 10, y: 4)
    }
}

struct NADAScreenBackground: View {
    var showBottomBlob: Bool = true

    var body: some View {
        ZStack {
            NADATheme.paper
            Circle()
                .fill(NADATheme.brandSoft.opacity(0.45))
                .frame(width: 320, height: 320)
                .blur(radius: 1)
                .offset(x: -120, y: -280)
            if showBottomBlob {
                Circle()
                    .fill(NADATheme.brand.opacity(0.07))
                    .frame(width: 260, height: 260)
                    .offset(x: 140, y: 320)
            }
        }
        .ignoresSafeArea()
    }
}

/// Branded splash — paper background + transparent logo mark.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            NADATheme.paper
            Image("SplashMark")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
        }
        .ignoresSafeArea()
    }
}

/// Blush capsule used for secondary actions next to a filled CTA.
struct NADASoftCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? NADATheme.hairline : NADATheme.brandSoft)
            .clipShape(Capsule())
    }
}

/// Ink capsule used for the primary profile action.
struct NADADarkCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NADATheme.ink.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(Capsule())
    }
}

struct NADASecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(NADATheme.brandSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
