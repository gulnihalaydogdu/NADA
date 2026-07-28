import SwiftUI

enum NADATheme {
    // NADA Lilac palette (§12) — light mode only for MVP
    static let paper = Color(red: 0.969, green: 0.961, blue: 0.980)       // #F7F5FA
    static let surface = Color(red: 0.937, green: 0.918, blue: 0.965)     // #EFEAF6
    static let ink = Color(red: 0.102, green: 0.086, blue: 0.145)         // #1A1625
    static let secondaryInk = Color(red: 0.435, green: 0.408, blue: 0.478) // #6F687A
    static let brand = Color(red: 0.722, green: 0.643, blue: 0.863)         // #B8A4DC
    static let brandPressed = Color(red: 0.608, green: 0.529, blue: 0.780)  // #9B87C7
    static let brandSoft = Color(red: 0.929, green: 0.902, blue: 0.969)    // #EDE6F7
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
                .fill(NADATheme.brandSoft.opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 1)
                .offset(x: -120, y: -280)
            Circle()
                .fill(NADATheme.brand.opacity(0.12))
                .frame(width: 260, height: 260)
                .offset(x: 140, y: 320)
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
