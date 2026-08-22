import SwiftUI

/// 홈 장소 카드 (`DESIGN.md` §6 카드).
///
/// ⚠️ 이름이 `PlaceCard`가 아니다 — 코스 미리보기의 `PlaceCard`(순번 마커가 붙은
/// 한 줄짜리 목록 항목)와 다른 물건이다. 같은 이름을 쓰면 컴파일이 안 된다.
///
/// 실사 사진 + 테두리 프레임이다 — 사진에 픽셀 필터를 씌우지 않는다(§1 절대 규칙).
/// 칩에는 **데이터에 실제로 있는 것만** 넣는다(`docs/공고.md` §4와 같은 원칙):
/// 실제 여행 일정 수와 해설 길이. 난이도·레벨 같은 건 만들 근거가 없다.
struct HomePlaceCard: View {
    let place: HomePlace
    /// 목록에서 딱 한 칸만 스티커를 붙인다 — 카드마다 붙으면 아무것도 안 튄다(§6).
    let isTopPick: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelCard {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    photo
                    Text(place.name)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: PixelSpacing.s) {
                        PixelChip(text: "해설 \(place.storyDurationText)", icon: .headphone,
                                  fill: PixelColor.tertiaryFixed,
                                  label: PixelColor.onTertiaryFixed)
                        PixelChip(text: "여행자 \(place.courseCount.formattedWithComma)명",
                                  icon: .person)
                    }
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 스티커는 카드 오른쪽 위로 튀어나온다(§6). `overlay`라야 카드 테두리를 넘는다.
            .overlay(alignment: .topTrailing) {
                if isTopPick {
                    PixelStickerBadge(text: "인기 픽")
                        .offset(x: PixelSpacing.s, y: -PixelSpacing.s)
                }
            }
        }
        .buttonStyle(.plain)
        // 카드 안의 글자가 그대로 읽히면 "해설 3분 7초, 여행자 2,668명"처럼 토막나 들린다.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name). 해설 \(place.storyDurationText). "
                            + "실제 여행 일정 \(place.courseCount)개에 담긴 곳"
                            + (isTopPick ? ". 인기 픽" : ""))
        .accessibilityAddTraits(.isButton)
    }

    /// 사진이 없는 곳도 있다(KTO에 사진이 없거나 아직 안 받아둔 곳).
    /// 카드가 무너지지 않게 같은 높이의 자리를 지킨다.
    @ViewBuilder
    private var photo: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let urlString = place.thumbnail, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
                    default:
                        PixelColor.surfaceHigh
                    }
                }
            } else {
                PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipped()
        .pixelBorder()
        .accessibilityHidden(true)
    }
}

extension Int {
    /// `2668` → `"2,668"`. 네 자리를 넘는 숫자를 카드에서 읽기 쉽게.
    var formattedWithComma: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}
