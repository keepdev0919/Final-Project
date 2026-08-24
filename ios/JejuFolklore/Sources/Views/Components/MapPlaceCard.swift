import SwiftUI

/// 지도에서 핀을 눌렀을 때 아래에서 올라오는 미니 카드.
///
/// **핀을 눌러도 화면이 넘어가지 않는다.** 이건 미리보기 단계이고, 장소 화면으로 가는 것은
/// 「자세히 보기」를 눌렀을 때뿐이다 (`docs/공유/Stitch-프롬프트_지도.md` 화면 2).
/// 그래서 카드는 화면 아래쪽만 덮어 지도와 눌린 핀이 계속 보이게 한다.
///
/// 홈의 `StageCard`와 다른 물건이다 — 저쪽은 「여기서 할 일」을 보여주는 스테이지 카드고,
/// 이쪽은 「눌린 게 어디인지」만 확인시키는 미리보기다. 그래서 미션도 라벨도 없다.
struct MapPlaceCard: View {
    let place: MapPlace
    let onClose: () -> Void
    let onOpen: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.m) {
                HStack(alignment: .top, spacing: PixelSpacing.m) {
                    thumbnail
                    VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                        Text(place.name)
                            .font(PixelFont.sectionTitle)
                            .foregroundStyle(PixelColor.ink)
                            .multilineTextAlignment(.leading)
                        PixelChip(text: "해설 \(place.storyDurationText)",
                                  icon: .headphone,
                                  fill: PixelColor.tertiaryFixed,
                                  label: PixelColor.onTertiaryFixed)
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        PixelIcon(.close, size: 24, color: PixelColor.inkWeak)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("닫기")
                }
                PixelButton(title: "자세히 보기", style: .primary, action: onOpen)
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 정사각 실사 사진. 사진이 없는 곳도 있어서 같은 크기의 자리를 지킨다.
    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let urlString = place.thumbnail, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: PixelIcon(.photo, size: 24, color: PixelColor.inkWeak)
                    default: PixelColor.surfaceHigh
                    }
                }
            } else {
                PixelIcon(.photo, size: 24, color: PixelColor.inkWeak)
            }
        }
        .frame(width: 72, height: 72)
        .clipped()
        .pixelBorder()
        .accessibilityHidden(true)
    }
}
