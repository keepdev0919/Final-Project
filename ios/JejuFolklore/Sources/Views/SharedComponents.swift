import SwiftUI

// MARK: - LoadingOverlay
struct LoadingOverlay: View {
    let step: LoadingStep

    var body: some View {
        ZStack {
            PixelColor.ink.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(PixelColor.onPrimary)
                Text(step.rawValue)
                    .font(PixelFont.label)
                    .foregroundColor(PixelColor.surface)
            }
            .padding(32)
            .background(PixelColor.surface)
        }
    }
}
