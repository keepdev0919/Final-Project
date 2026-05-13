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
                    .tint(.white)
                Text(step.rawValue)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
