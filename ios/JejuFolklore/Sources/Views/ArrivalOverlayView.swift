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
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.orange)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                }

                // 도착 메시지
                VStack(spacing: 8) {
                    Text("설화 장소에 도착했습니다")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(place.name)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)

                // 버튼
                //
                // 단계 1에서 여기가 "이야기 듣기" 진입점이 된다. 설화 채팅을
                // 제거(2026-08-13)한 지금은 확인 버튼 하나만 둔다.
                VStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("확인")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
    let mockPlace = CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1, folklorePins: [])
    ArrivalOverlayView(
        place: mockPlace,
        onDismiss: {}
    )
}
