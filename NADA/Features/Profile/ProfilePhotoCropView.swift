import SwiftUI
import UIKit

/// Pan + pinch editor so the user picks which square of a photo becomes their profile picture.
struct ProfilePhotoCropView: View {
    let source: UIImage
    var onCancel: () -> Void
    var onReplace: (() -> Void)?
    var onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 280

    private var normalized: UIImage {
        source.normalizedOrientation()
    }

    var body: some View {
        // NavigationStack keeps Cancel / Done inside the system safe area —
        // custom top bars under fullScreenCover were sliding under the status bar.
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    cropArea
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    resetButton
                        .padding(.top, 14)

                    hintCard
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 32)
                }
            }
            .background {
                // Color only — do NOT use NADAScreenBackground here.
                // Its .ignoresSafeArea() expands the layout and pulls content under the status bar.
                ZStack {
                    NADATheme.paper
                    Circle()
                        .fill(NADATheme.brandSoft.opacity(0.45))
                        .frame(width: 320, height: 320)
                        .blur(radius: 1)
                        .offset(x: -120, y: -200)
                    Circle()
                        .fill(NADATheme.brand.opacity(0.07))
                        .frame(width: 260, height: 260)
                        .offset(x: 140, y: 420)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(NADATheme.brandPressed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if let cropped = renderCrop() {
                            onCrop(cropped)
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NADATheme.brandPressed)
                }
            }
            .toolbarBackground(NADATheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var cropArea: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let crop = CGSize(width: side, height: side)

            ZStack {
                Image(uiImage: normalized)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: side, height: side)
                    .clipped()
                    .gesture(dragGesture(cropSize: crop))
                    .simultaneousGesture(magnifyGesture(cropSize: crop))

                CropGrid()
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                if let onReplace {
                    VStack {
                        HStack {
                            Spacer()
                            replaceButton(action: onReplace)
                        }
                        Spacer()
                    }
                    .frame(width: side, height: side)
                    .padding(12)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                cropSide = side
                resetFraming(cropSize: crop)
            }
            .onChange(of: side) { _, newSide in
                cropSide = newSide
                clampOffset(cropSize: CGSize(width: newSide, height: newSide))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func replaceButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Replace Photo", systemImage: "camera")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.paper)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(NADATheme.ink.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button("Reset framing") {
            resetFraming(cropSize: CGSize(width: cropSide, height: cropSide))
        }
        .font(NADATheme.captionFont)
        .foregroundStyle(NADATheme.brandPressed)
    }

    private var hintCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NADATheme.brand)

            Text("Drag to move and pinch to zoom. Everything inside the square is saved.")
                .font(NADATheme.captionFont)
                .foregroundStyle(NADATheme.warmSecondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(NADATheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NADATheme.ink.opacity(0.08), lineWidth: 1)
        )
    }

    private func dragGesture(cropSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                clampOffset(cropSize: cropSize)
            }
    }

    private func magnifyGesture(cropSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 4)
                clampOffset(cropSize: cropSize)
            }
            .onEnded { _ in
                lastScale = scale
                clampOffset(cropSize: cropSize)
            }
    }

    /// Size the aspect-fill image occupies inside the crop square before zoom.
    private func imageDisplaySize(for cropSize: CGSize) -> CGSize {
        let imageSize = normalized.size
        guard imageSize.width > 0, imageSize.height > 0 else { return cropSize }
        let cover = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
        return CGSize(width: imageSize.width * cover, height: imageSize.height * cover)
    }

    private func clampOffset(cropSize: CGSize) {
        let display = imageDisplaySize(for: cropSize)
        let limit = CGSize(
            width: max(0, (display.width * scale - cropSize.width) / 2),
            height: max(0, (display.height * scale - cropSize.height) / 2)
        )
        offset = CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
        lastOffset = offset
    }

    private func resetFraming(cropSize: CGSize) {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        clampOffset(cropSize: cropSize)
    }

    private func renderCrop() -> UIImage? {
        let outputSide: CGFloat = 1200
        let image = normalized
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, cropSide > 0 else { return nil }

        // Match the on-screen layout: aspect-fill into the crop square, then scale + offset.
        let fillScale = max(cropSide / imageSize.width, cropSide / imageSize.height)
        let effectiveScale = fillScale * scale
        let drawnWidth = imageSize.width * effectiveScale
        let drawnHeight = imageSize.height * effectiveScale
        let imageOrigin = CGPoint(
            x: (cropSide - drawnWidth) / 2 + offset.width,
            y: (cropSide - drawnHeight) / 2 + offset.height
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: format
        )
        let viewToOutput = outputSide / cropSide

        return renderer.image { _ in
            image.draw(in: CGRect(
                x: imageOrigin.x * viewToOutput,
                y: imageOrigin.y * viewToOutput,
                width: drawnWidth * viewToOutput,
                height: drawnHeight * viewToOutput
            ))
        }
    }
}

/// Rule-of-thirds guides drawn over the crop square.
private struct CropGrid: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                Path { path in
                    for index in 1...2 {
                        let x = width / 3 * CGFloat(index)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))

                        let y = height / 3 * CGFloat(index)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.65), lineWidth: 1)

                Rectangle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            }
        }
    }
}

private extension UIImage {
    /// Fixes camera/library orientation so crop math uses upright pixels.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#Preview {
    ProfilePhotoCropView(
        source: UIImage(systemName: "person.crop.square.fill") ?? UIImage(),
        onCancel: {},
        onCrop: { _ in }
    )
}
