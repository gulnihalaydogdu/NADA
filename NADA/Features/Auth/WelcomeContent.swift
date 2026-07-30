import SwiftUI

enum WelcomeContent {
    static let sketchImage = "SketchWelcomeHangout"
    static let headline = "Hang out, not match."
    static let subline = "Meet people nearby for\ncoffee, walks and real-life plans."
}

/// The source PNG has large empty margins, so it is scaled to fill the width
/// and cropped to the band that actually contains the drawing.
struct WelcomeIllustration: View {
    var height: CGFloat
    var horizontalPadding: CGFloat = 8
    var verticalShift: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay {
                Image(WelcomeContent.sketchImage)
                    .resizable()
                    .scaledToFill()
                    .offset(y: verticalShift)
            }
            .clipped()
            .padding(.horizontal, horizontalPadding)
    }
}
