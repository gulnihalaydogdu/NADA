import SwiftUI
import UIKit

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

    /// Tab-bar like-count bubble — dusty coral, not system red.
    /// Do not assign `UITabBarAppearance` here: it flattens iOS 26’s glass tab bar.
    static func applyTabBadgeAppearance() {
        let coral = UIColor(red: 0.757, green: 0.482, blue: 0.435, alpha: 1)
        let onCoral = UIColor(red: 0.980, green: 0.973, blue: 0.965, alpha: 1)
        let text: [NSAttributedString.Key: Any] = [
            .foregroundColor: onCoral,
            .font: UIFont.systemFont(ofSize: 11, weight: .bold)
        ]

        UITabBarItem.appearance().badgeColor = coral
        UITabBarItem.appearance().setBadgeTextAttributes(text, for: .normal)
        UITabBarItem.appearance().setBadgeTextAttributes(text, for: .selected)
    }

    static let titleFont = Font.system(.title, design: .default, weight: .bold)
    static let displayFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(.headline, design: .default, weight: .semibold)
    static let bodyFont = Font.system(.body, design: .default)
    static let captionFont = Font.system(.caption, design: .default)

    /// Shared registration / setup spacing — keep screens in the same rhythm.
    enum Layout {
        static let screenPadding: CGFloat = 24
        static let titleToSubtitle: CGFloat = 8
        static let headerToContent: CGFloat = 24
        static let fieldSpacing: CGFloat = 14
        static let fieldRadius: CGFloat = 12
        static let fieldMinHeight: CGFloat = 52
        static let fieldHPadding: CGFloat = 16
        static let footerTop: CGFloat = 14
        static let footerBottom: CGFloat = 16
        static let progressHeight: CGFloat = 4
        static let backHit: CGFloat = 36
        static let ctaRadius: CGFloat = 14
        static let ctaMinHeight: CGFloat = 52
    }
}

struct NADAPrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(NADATheme.headlineFont)
            .foregroundStyle(NADATheme.onBrand.opacity(isEnabled ? 1 : 0.92))
            .frame(maxWidth: .infinity, minHeight: NADATheme.Layout.ctaMinHeight)
            .background(isEnabled ? (pressed ? NADATheme.brandPressed : NADATheme.brand) : NADATheme.brand.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: NADATheme.Layout.ctaRadius, style: .continuous))
            .shadow(
                color: NADATheme.brand.opacity(isEnabled ? (pressed ? 0.08 : 0.18) : 0),
                radius: isEnabled ? 10 : 0,
                y: isEnabled ? 4 : 0
            )
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Primary CTA without SwiftUI’s default disabled fade (which made buttons look broken).
    func nadaPrimaryCTA(enabled: Bool) -> some View {
        self
            .buttonStyle(NADAPrimaryButtonStyle(isEnabled: enabled))
            .allowsHitTesting(enabled)
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
