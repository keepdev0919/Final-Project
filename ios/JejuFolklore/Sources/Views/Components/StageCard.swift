import SwiftUI

/// 홈 스테이지 카드 (`DESIGN.md` §6 카드).
///
/// **장소를 설명하지 않는다.** 게임의 스테이지 선택 화면처럼 「여기서 할 일」과 「내 상태」만
/// 보여준다. 해설 길이·일정 수·운영시간은 전부 장소 상세로 내렸다.
///
/// ## 넷을 담으면서 카드가 벽이 되지 않게 하는 방법
///
/// 세계관 라벨 · 내 상태 · 할 일 · 보상 네 가지를 다 담는다. 넷을 다 문장으로 쓰면
/// 카드 높이가 450pt가 되어 화면에 1.5장만 보인다. 그래서 **셋을 그림·기호로 옮기고
/// 문장은 하나만** 둔다.
///
/// | 무엇 | 어디에 |
/// |---|---|
/// | 세계관 라벨 | 사진 안 왼쪽 위 칩 |
/// | 내 상태 | 사진 위 도장 |
/// | **할 일** | **카드의 유일한 문장** — 그래서 제일 먼저 읽힌다 |
/// | 보상 | 물음표 칸, 라벨 없이 |
///
/// ## 진행 바가 없는 이유
///
/// 시안에는 「난이도 바」가 있었고 그 자리를 진행 바로 쓰려 했다. 그런데 지점 수가 아직
/// 정해진 데이터가 아니라(`docs/공고.md` §3 P0-5 — 지점은 콘텐츠 작업 때 정한다)
/// `0/4`의 4가 근거 없는 숫자가 된다. 진행 기록도 없어 카드 6장의 바가 전부 똑같이 빈다.
/// **지점과 바는 실제 값이 생길 때 붙인다.** 그때까지 상태는 도장이 진다.
struct StageCard: View {
    let stage: HomeStage
    let action: () -> Void

    // 「인기 픽」 스티커는 두지 않는다. 카드 6장이 **각자 자기 종류의 1등**이라
    // 한 장만 튀게 할 근거가 없고, 사진 모서리는 라벨 칩과 도장이 이미 쓰고 있다.

    /// 보상 물음표 칸 수. 무엇을 얻는지는 아직 정해지지 않았고, 정해지지 않은 것을
    /// 물음표로 두는 것이 카드에서 가장 정직한 표현이다.
    private let unknownRewardCount = 3

    var body: some View {
        Button(action: action) {
            PixelCard {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    photo
                    Text(stage.name)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(stage.mission)
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    rewardRow
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stage.labelName) 지역, \(stage.name). 아직 밟지 않은 곳. "
            + "할 일: \(stage.mission)"
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 사진 + 그 위에 얹는 것

    @ViewBuilder
    private var photo: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let urlString = stage.thumbnail, let url = URL(string: urlString) {
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
        .overlay(alignment: .topLeading) { labelChip }
        .overlay(alignment: .bottomLeading) { statusStamp }
        .pixelBorder()
        .accessibilityHidden(true)
    }

    /// 세계관 라벨. 사진 안에 두는 것은 시안 방식이다 — 시안도 사진 왼쪽 위에
    /// 작은 아이콘과 지역 태그를 넣었다. 카드 본문 줄을 하나 아끼는 효과가 있다.
    private var labelChip: some View {
        HStack(spacing: PixelSpacing.xs) {
            if let glyph = stage.labelGlyph {
                PixelIcon(glyph, size: 16, color: PixelColor.onAccent)
            }
            Text(stage.labelName)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.onAccent)
        }
        .padding(.horizontal, PixelSpacing.s)
        .padding(.vertical, PixelSpacing.xs)
        .background(PixelColor.accent)
        .pixelBorder()
        .padding(PixelSpacing.s)
    }

    /// 내 상태 도장. 지금은 전부 「미탐험」이고, 플레이 기록이 붙으면 여기가
    /// 「클리어」 도장으로 바뀐다. 도장이 상태를 지고 있어서 진행 바가 없어도 된다.
    private var statusStamp: some View {
        Text("미탐험")
            .font(PixelFont.label)
            .foregroundStyle(PixelColor.onLocked)
            .padding(.horizontal, PixelSpacing.s)
            .padding(.vertical, PixelSpacing.xs)
            .background(PixelColor.locked)
            .pixelBorder()
            .rotationEffect(.degrees(-3))
            .padding(PixelSpacing.s)
    }

    // MARK: - 보상

    /// 무엇을 얻는지 아직 정해지지 않았으니 물음표만 둔다. 실루엣이 보이면 궁금해지고,
    /// 다녀오면 도트가 채워진다(수집물 그림은 묶음 3에서 그린다 — `DESIGN.md` §9).
    private var rewardRow: some View {
        HStack(spacing: PixelSpacing.s) {
            ForEach(0..<unknownRewardCount, id: \.self) { _ in
                Text("?")
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.inkWeak)
                    .frame(width: 28, height: 28)
                    .background(PixelColor.surfaceLow)
                    .pixelBorder()
            }
            Spacer(minLength: 0)
        }
    }
}
