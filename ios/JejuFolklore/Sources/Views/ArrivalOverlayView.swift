import SwiftUI

struct ArrivalOverlayView: View {
    let place: CoursePlace
    let companion: CompanionCharacter
    let onEnterChat: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // 동행자 이모지 + 이름
                VStack(spacing: 8) {
                    Text(companion.emoji)
                        .font(.system(size: 72))
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)

                    Text(companion.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.orange)
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

                // 동행자 첫마디
                Text("\"\(companion.greeting)\"")
                    .font(.subheadline.italic())
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)

                // 버튼
                VStack(spacing: 12) {
                    Button(action: onEnterChat) {
                        Text("동행자와 대화하기")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: onDismiss) {
                        Text("나중에")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
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
        companion: .hallam,
        onEnterChat: {},
        onDismiss: {}
    )
}
