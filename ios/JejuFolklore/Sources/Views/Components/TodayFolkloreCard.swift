import SwiftUI

/// 홈 상단의 "오늘의 설화" 히어로 카드.
/// - hero 이미지(16:9), 라벨, 제목, 후크, "이야기 보기" 버튼
/// - 카드 탭: `onTapCard()` (지도 줌인 등)
/// - 버튼 탭: `onTapStory()` (상세 화면 진입)
struct TodayFolkloreCard: View {
    let folklore: TodayFolklore
    let onTapCard: () -> Void
    let onTapStory: () -> Void

    var body: some View {
        Button(action: onTapCard) {
            VStack(alignment: .leading, spacing: 0) {
                heroImage
                infoSection
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero image

    private var heroImage: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let urlString = folklore.heroImage,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            placeholderGradient
                                .overlay(ProgressView().tint(.white))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placeholderGradient
                        @unknown default:
                            placeholderGradient
                        }
                    }
                } else {
                    placeholderGradient
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0/9.0, contentMode: .fill)
            .clipped()

            // 라벨 (좌상단)
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("오늘의 설화")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.orange.opacity(0.92))
            )
            .padding(12)
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "book.closed.fill")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.7))
        )
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(folklore.displayTitle)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(folklore.hook)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(alignment: .center) {
                if !folklore.primaryPlace.isEmpty {
                    Label(folklore.primaryPlace, systemImage: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onTapStory) {
                    HStack(spacing: 4) {
                        Text("이야기 보기")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.orange)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(14)
    }
}
