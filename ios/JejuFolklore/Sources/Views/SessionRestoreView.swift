import SwiftUI

/// 앱 재실행 시 저장된 탐험 세션이 있을 때 표시되는 복원 화면.
struct SessionRestoreView: View {
    let session: TravelSession
    let onResume: (Course, String) -> Void    // course, transport
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PixelColor.inkWeak.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 20) {
                PixelIcon(.mapPin, size: 48, color: PixelColor.primary)

                VStack(spacing: 6) {
                    Text("탐험 중인 코스가 있어요")
                        .font(PixelFont.bodyLarge)

                    Text(session.courseSnapshot.title)
                        .font(PixelFont.body)
                        .foregroundColor(PixelColor.inkWeak)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PixelIcon(.mapPin, size: 18)
                            .foregroundColor(PixelColor.primary)
                        Text("방문 완료: \(session.visitedPlaceNames.count) / \(session.courseSnapshot.places.count)곳")
                            .font(PixelFont.body)
                    }

                    HStack {
                        PixelIcon(.clock, size: 18)
                            .foregroundColor(PixelColor.primary)
                        Text("시작: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(PixelFont.body)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PixelColor.primary.opacity(0.08))
                .clipShape(Rectangle())

                VStack(spacing: 10) {
                    Button {
                        onResume(session.courseSnapshot, session.transport)
                    } label: {
                        Label { Text("이어서 탐험하기") } icon: { PixelIcon(.mapPin, size: 16) }
                            .font(PixelFont.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(PixelColor.primary)
                            .foregroundColor(PixelColor.surface)
                            .clipShape(Rectangle())
                    }

                    Button(role: .destructive) {
                        onDiscard()
                    } label: {
                        Text("탐험 종료하기")
                            .font(PixelFont.body)
                            .foregroundColor(PixelColor.inkWeak)
                    }
                }
            }
            .padding(24)
        }
        .background(PixelColor.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
