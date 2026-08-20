import SwiftUI

struct ArrivalOverlayView: View {
    let place: CoursePlace
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // 도착 표시. 단계 1에서 여기에 곱닥이 캐릭터가 들어간다.
                VStack(spacing: 8) {
                    // 어둠막 위라 밝은 금색으로. 적응색(primary)은 라이트 모드에서
                    // 진한 초록이 되어 검은 막에 묻힌다.
                    PixelIcon(.mapPin, size: 72, color: PixelColor.tertiaryFixed)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                }

                // 도착 메시지
                VStack(spacing: 8) {
                    Text("이야기가 준비된 곳이에요")
                        .font(PixelFont.sectionTitle)
                        .foregroundColor(PixelColor.surface)
                        .multilineTextAlignment(.center)

                    Text(place.name)
                        .font(PixelFont.bodyLarge)
                        .foregroundColor(PixelColor.surface.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)

                // 버튼
                //
                // 묶음 B에서 여기가 "이야기 듣기" 진입점이 된다.
                // 지금은 확인 버튼 하나만 둔다.
                VStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("확인")
                            .font(PixelFont.body)
                            .foregroundColor(PixelColor.surface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PixelColor.primary)
                            .clipShape(Rectangle())
                    }
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.vertical, 48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

#Preview {
    let mockPlace = CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1)
    ArrivalOverlayView(
        place: mockPlace,
        onDismiss: {}
    )
}
