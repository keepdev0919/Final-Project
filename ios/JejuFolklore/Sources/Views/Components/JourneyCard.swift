import SwiftUI

/// 여정·장소 카드 (DESIGN.md §6).
///
/// 실사 사진 + 테두리 프레임 조합이다 — 사진에 픽셀 필터를 씌우지 않는다(§1 절대 규칙).
struct JourneyCard: View {
    let journey: Journey
    let isNearby: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelCard {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    coverImage
                    Text(journey.title)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                        .multilineTextAlignment(.leading)

                    if !journey.subtitle.isEmpty {
                        Text(journey.subtitle)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: PixelSpacing.s) {
                        PixelChip(text: "이야기 \(journey.storyCount)개")
                        PixelChip(text: "\(journey.totalMinutes)분", icon: .play,
                                  fill: PixelColor.tertiaryFixed,
                                  label: PixelColor.onTertiaryFixed)
                    }

                    HStack(spacing: PixelSpacing.s) {
                        PixelBadge(text: "앞부분 무료", kind: .free)
                        if isNearby {
                            PixelBadge(text: "지금 여기예요", kind: .here)
                        }
                    }
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    /// 커버 사진이 아직 없으면 단색 자리로 둔다 (DESIGN.md §8 — 그림 파일은 후순위).
    @ViewBuilder
    private var coverImage: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let urlString = journey.coverImage, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    PixelColor.surfaceHigh
                }
            } else {
                PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
            }
        }
        .frame(height: 160)
        .clipped()
        .pixelBorder()
    }
}
