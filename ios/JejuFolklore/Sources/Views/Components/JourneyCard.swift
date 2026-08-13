import SwiftUI

/// DESIGN.md §6 "장소 카드". 홈 최상단에 가장 크게 놓인다.
///
/// 실사 사진 + 픽셀 프레임 조합이다 (§1 절대 규칙 — 사진에 픽셀 필터를 씌우지 않는다).
struct JourneyCard: View {
    let journey: Journey
    let isNearby: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelCard {
                VStack(alignment: .leading, spacing: 0) {
                    coverImage
                    VStack(alignment: .leading, spacing: PixelSpacing.s) {
                        Text(journey.title)
                            .pixelFont(PixelFont.cardTitle)
                            .foregroundStyle(PixelColor.ink)
                            .multilineTextAlignment(.leading)

                        Text(journey.subtitle)
                            .pixelFont(PixelFont.badge)
                            .foregroundStyle(PixelColor.inkWeak)

                        Text("이야기 \(journey.storyCount)개 · \(journey.totalMinutes)분")
                            .pixelFont(PixelFont.badge)
                            .foregroundStyle(PixelColor.inkWeak)

                        HStack(spacing: PixelSpacing.s) {
                            PixelBadge(text: "앞부분 무료", kind: .free)
                            if isNearby {
                                PixelBadge(text: "지금 여기예요", kind: .here)
                            }
                        }
                        .padding(.top, PixelSpacing.xs)
                    }
                    .padding(PixelSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 커버 사진이 아직 없으면 단색 자리로 둔다 (DESIGN.md §8 — 그림 파일은 후순위).
    @ViewBuilder
    private var coverImage: some View {
        ZStack {
            PixelColor.primary
            if let urlString = journey.coverImage, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    PixelColor.primary
                }
            } else {
                PixelIcon(.mapPin, size: 48, color: PixelColor.surface)
            }
        }
        .frame(height: 180)
        .clipped()
    }
}
