import SwiftUI
import UIKit

/// Pan + pinch crop editor. Use `aspectWidthOverHeight` of `1` (square) or `0.75` (3:4 portrait).
struct ProfilePhotoCropView: View {
    let source: UIImage
    /// Crop frame width ÷ height. `1` = square primary, `3/4` = gallery portrait.
    var aspectWidthOverHeight: CGFloat = 1
    var title: String = "Edit Photo"
    var subtitle: String?
    var onCancel: () -> Void
    var onReplace: (() -> Void)?
    var onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropSize: CGSize = CGSize(width: 280, height: 280)
    @State private var isRendering = false

    private let normalized: UIImage

    init(
        source: UIImage,
        aspectWidthOverHeight: CGFloat = 1,
        title: String = "Edit Photo",
        subtitle: String? = nil,
        onCancel: @escaping () -> Void,
        onReplace: (() -> Void)? = nil,
        onCrop: @escaping (UIImage) -> Void
    ) {
        self.source = source
        self.aspectWidthOverHeight = aspectWidthOverHeight
        self.title = title
        self.subtitle = subtitle
        self.onCancel = onCancel
        self.onReplace = onReplace
        self.onCrop = onCrop
        self.normalized = source.normalizedOrientation()
    }

    private var isSquare: Bool { abs(aspectWidthOverHeight - 1) < 0.01 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let subtitle {
                        Text(subtitle)
                            .font(NADATheme.captionFont)
                            .foregroundStyle(NADATheme.secondaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }

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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(NADATheme.brandPressed)
                        .disabled(isRendering)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        confirmCrop()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NADATheme.brandPressed)
                    .disabled(isRendering)
                }
            }
            .toolbarBackground(NADATheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// Keep Done disabled until this crop is handed off — resetting `isRendering`
    /// before `onCrop` let a second tap save the same photo twice.
    private func confirmCrop() {
        guard !isRendering else { return }
        isRendering = true
        Task {
            let cropped = await renderCropOffMain()
            guard let cropped else {
                isRendering = false
                return
            }
            onCrop(cropped)
        }
    }

    private var cropArea: some View {
        GeometryReader { geo in
            let fitted = fittedCropSize(in: geo.size)
            ZStack {
                Image(uiImage: normalized)
                    .resizable()
                    .scaledToFill()
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipped()
                    .gesture(dragGesture(cropSize: fitted))
                    .simultaneousGesture(magnifyGesture(cropSize: fitted))

                CropGrid()
                    .frame(width: fitted.width, height: fitted.height)
                    .allowsHitTesting(false)

                if let onReplace {
                    VStack {
                        HStack {
                            Spacer()
                            replaceButton(action: onReplace)
                        }
                        Spacer()
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .padding(12)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                cropSize = fitted
                resetFraming(cropSize: fitted)
            }
            .onChange(of: geo.size) { _, newSize in
                let next = fittedCropSize(in: newSize)
                cropSize = next
                clampOffset(cropSize: next)
            }
        }
        .aspectRatio(aspectWidthOverHeight, contentMode: .fit)
    }

    private func fittedCropSize(in container: CGSize) -> CGSize {
        let ratio = max(aspectWidthOverHeight, 0.01)
        let width = container.width
        let height = width / ratio
        if height <= container.height {
            return CGSize(width: width, height: height)
        }
        let fittedHeight = container.height
        return CGSize(width: fittedHeight * ratio, height: fittedHeight)
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
            resetFraming(cropSize: cropSize)
        }
        .font(NADATheme.captionFont)
        .foregroundStyle(NADATheme.brandPressed)
    }

    private var hintCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NADATheme.brand)

            Text(
                isSquare
                    ? "Drag to move and pinch to zoom. Everything inside the square is saved."
                    : "Drag to move and pinch to zoom. Everything inside the 3:4 frame is saved."
            )
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

    /// Exports the framed crop without blocking the main thread on the 1200px draw.
    private func renderCropOffMain() async -> UIImage? {
        let imageSize = normalized.size
        guard imageSize.width > 0, imageSize.height > 0,
              cropSize.width > 0, cropSize.height > 0 else { return nil }

        let box = UncheckedBox(normalized)
        let cropSize = cropSize
        let offset = offset
        let scale = scale
        let aspect = aspectWidthOverHeight

        return await ImageProcessing.render {
            let fillScale = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
            let effectiveScale = fillScale * scale
            let drawnWidth = imageSize.width * effectiveScale
            let drawnHeight = imageSize.height * effectiveScale
            let imageOrigin = CGPoint(
                x: (cropSize.width - drawnWidth) / 2 + offset.width,
                y: (cropSize.height - drawnHeight) / 2 + offset.height
            )

            let outputHeight: CGFloat = 1200
            let outputWidth = outputHeight * aspect
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: outputWidth, height: outputHeight),
                format: format
            )
            let scaleX = outputWidth / cropSize.width
            let scaleY = outputHeight / cropSize.height

            return renderer.image { _ in
                box.value.draw(in: CGRect(
                    x: imageOrigin.x * scaleX,
                    y: imageOrigin.y * scaleY,
                    width: drawnWidth * scaleX,
                    height: drawnHeight * scaleY
                ))
            }
        }
    }
}

/// Rule-of-thirds guides drawn over the crop frame.
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
        aspectWidthOverHeight: 3.0 / 4.0,
        onCancel: {},
        onCrop: { _ in }
    )
}
