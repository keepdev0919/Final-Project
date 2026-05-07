import SwiftUI

struct DaySummaryView: View {
    let visitedPlaces: [String]
    let companion: CompanionCharacter
    let onGenerateJournal: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // 동행자 완료 메시지
                    VStack(spacing: 10) {
                        Text(companion.emoji)
                            .font(.system(size: 64))
                        Text("오늘 여행을 마쳤어요!")
                            .font(.title2.weight(.bold))
                        Text("\(companion.emoji) \(companion.displayName)과 함께한 하루")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                        Text("아이고, 삼춘~ 잘도 열심히 다녔구만요~")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // 탐험 통계 요약
                    HStack(spacing: 12) {
                        StatBadgeView(
                            icon: "mappin.circle.fill",
                            value: "\(visitedPlaces.count)곳",
                            label: "방문",
                            color: .orange
                        )
                        StatBadgeView(
                            icon: "book.closed.fill",
                            value: visitedPlaces.isEmpty ? "-" : "\(visitedPlaces.count * 3)개",
                            label: visitedPlaces.isEmpty ? "설화 정보 없음" : "설화",
                            color: .purple
                        )
                    }

                    // 방문 장소 목록
                    VStack(alignment: .leading, spacing: 0) {
                        Text("방문한 장소")
                            .font(.headline)
                            .padding(.bottom, 12)

                        if visitedPlaces.isEmpty {
                            Text("방문한 장소가 없어요.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(visitedPlaces.indices, id: \.self) { i in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 26, height: 26)
                                        Text("\(i + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                    }
                                    Text(visitedPlaces[i])
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.subheadline)
                                }
                                .padding(.vertical, 10)

                                if i < visitedPlaces.count - 1 {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                    // 일지 생성 버튼
                    Button(action: onGenerateJournal) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                            Text("여행 일지 생성하기")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("여행 요약")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기", action: onDismiss)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct StatBadgeView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold))
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DaySummaryView(
        visitedPlaces: ["성산일출봉", "섭지코지", "협재해수욕장"],
        companion: .hallam,
        onGenerateJournal: {},
        onDismiss: {}
    )
}
