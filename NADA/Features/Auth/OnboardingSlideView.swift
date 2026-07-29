import SwiftUI

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let imageName: String?
    let systemImage: String?
    let headline: String
    let subline: String

    static let welcomePages: [OnboardingSlide] = [
        OnboardingSlide(
            imageName: "SketchWelcomeHangout",
            systemImage: nil,
            headline: "Hang out, not match.",
            subline: "Profiles built for plans — coffee, walks, game night."
        ),
        OnboardingSlide(
            imageName: "SketchWelcomeBits",
            systemImage: nil,
            headline: "Let your profile speak for you.",
            subline: "Photos and bits — see who you'd actually hang with."
        ),
        OnboardingSlide(
            imageName: "SketchWelcomeConfidence",
            systemImage: nil,
            headline: "Meet with confidence.",
            subline: "No flirting pressure. No video calls. Just hangouts."
        )
    ]
}

struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    var showsText: Bool = true
    var illustrationHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 20) {
            illustration

            if showsText {
                VStack(spacing: 12) {
                    Text(slide.headline)
                        .font(NADATheme.displayFont)
                        .foregroundStyle(NADATheme.ink)
                        .multilineTextAlignment(.center)

                    Text(slide.subline)
                        .font(NADATheme.bodyFont)
                        .foregroundStyle(NADATheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var illustration: some View {
        if let imageName = slide.imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(height: illustrationHeight)
                .padding(.horizontal, 28)
        } else if let systemImage = slide.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(NADATheme.brand)
                .frame(height: illustrationHeight)
        }
    }
}
