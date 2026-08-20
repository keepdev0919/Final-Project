import SwiftUI

// MARK: - LoadingOverlay
struct LoadingOverlay: View {
    let step: LoadingStep

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(PixelColor.primary)
                Text(step.rawValue)
                    .font(PixelFont.label)
                    .foregroundColor(PixelColor.ink)
            }
            .padding(32)
            .background(PixelColor.surface)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowCard)
        }
    }
}
