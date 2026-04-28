import SwiftUI

/// 앱 재실행 시 저장된 탐험 세션이 있을 때 표시되는 복원 화면.
struct SessionRestoreView: View {
    let session: TravelSession
    let onResume: (Course, String) -> Void    // course, transport
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 20) {
                Text(session.companion.emoji)
                    .font(.system(size: 48))

                VStack(spacing: 6) {
                    Text("탐험 중인 코스가 있어요")
                        .font(.title3.weight(.bold))

                    Text(session.courseSnapshot.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.orange)
                        Text("방문 완료: \(session.visitedPlaceNames.count) / \(session.courseSnapshot.places.count)곳")
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                        Text("시작: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 10) {
                    Button {
                        onResume(session.courseSnapshot, session.transport)
                    } label: {
                        Label("이어서 탐험하기", systemImage: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(role: .destructive) {
                        onDiscard()
                    } label: {
                        Text("탐험 종료하기")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
