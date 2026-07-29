import SwiftUI

enum NADATheme {
    // NADA Lilac palette (§12) — light mode only for MVP
    static let paper = Color(red: 0.969, green: 0.961, blue: 0.980)       // #F7F5FA
    static let surface = Color(red: 0.937, green: 0.918, blue: 0.965)     // #EFEAF6
    static let ink = Color(red: 0.102, green: 0.086, blue: 0.145)         // #1A1625
    static let secondaryInk = Color(red: 0.435, green: 0.408, blue: 0.478) // #6F687A
    static let warmSecondaryInk = Color(red: 0.361, green: 0.337, blue: 0.408) // #5C5668
    static let brand = Color(red: 0.722, green: 0.643, blue: 0.863)         // #B8A4DC
    static let brandPressed = Color(red: 0.608, green: 0.529, blue: 0.780)  // #9B87C7
    static let brandSoft = Color(red: 0.929, green: 0.902, blue: 0.969)    // #EDE6F7
    static let coral = Color(red: 0.757, green: 0.482, blue: 0.435)         // #C17B6F — sketch accent
    static let coralPressed = Color(red: 0.647, green: 0.392, blue: 0.345)  // pressed
    static let onCoral = Color(red: 0.969, green: 0.961, blue: 0.980)       // light on coral CTA
    static let danger = Color(red: 0.706, green: 0.137, blue: 0.094)       // #B42318
    static let hairline = Color(red: 0.878, green: 0.851, blue: 0.922)    // #E0D9EB

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
            .foregroundStyle(NADATheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(configuration.isPressed ? NADATheme.brandPressed : NADATheme.brand)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Welcome / hero CTA — ties to sketch coral accent.
struct NADACoralPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.onCoral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(configuration.isPressed ? NADATheme.coralPressed : NADATheme.coral)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: NADATheme.coral.opacity(configuration.isPressed ? 0.1 : 0.22), radius: 10, y: 4)
    }
}

struct NADATextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NADATheme.bodyFont.weight(.medium))
            .foregroundStyle(NADATheme.secondaryInk)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct NADAScreenBackground: View {
    var body: some View {
        ZStack {
            NADATheme.paper
            Circle()
                .fill(NADATheme.brandSoft.opacity(0.4))
                .frame(width: 320, height: 320)
                .blur(radius: 1)
                .offset(x: -120, y: -280)
            Circle()
                .fill(NADATheme.brand.opacity(0.06))
                .frame(width: 260, height: 260)
                .offset(x: 140, y: 320)
        }
        .ignoresSafeArea()
    }
}

/// Welcome hero — single soft blob, no bottom circle competing with CTA.
struct NADAWelcomeBackground: View {
    var body: some View {
        ZStack {
            NADATheme.paper
            Circle()
                .fill(NADATheme.brandSoft.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 1)
                .offset(x: -100, y: -260)
        }
        .ignoresSafeArea()
    }
}

/// Branded splash — launch screen + resume overlay.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            NADATheme.paper
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
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
