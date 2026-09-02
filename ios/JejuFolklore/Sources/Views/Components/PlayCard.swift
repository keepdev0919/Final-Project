import SwiftUI

/// 퀘스트 카드 — 홈의 주인공.
///
/// 시안(2026-09-02) 그대로다. 활성과 준비 중이 **같은 크기·같은 뼈대**를 쓰고,
/// 사진의 색과 자물쇠, 버튼 상태로만 갈린다. 크기가 다르면 목록이 들쭉날쭉해지고
/// "준비 중인 곳도 언젠가 이만큼 된다"는 인상이 사라진다.
///
///     [커버]
///     성읍 생활기록 복원작전        🕐 60-75분
///     ★★☆☆☆
///     네 채의 집을 직접 조사하여…
///     [ 퀘스트 수락 ]
///
/// 거리와 미션 수는 **일부러 뺐다**(조익준님 결정). 카드가 벽이 되지 않게
/// 하고, 그 둘은 PLAY 상세에서 보여준다.
struct PlayCard: View {
    let play: PlaySummary
    /// 진행 중이면 「이어서 하기」처럼 버튼 문구가 바뀐다.
    var progressText: String? = nil
    let action: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                cover
                VStack(alignment: .leading, spacing: PixelSpacing.s) {
                    titleRow
                    StarRating(filled: play.difficultyStars)
                    if !play.objective.isEmpty {
                        Text(play.objective)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PixelButton(title: progressText ?? "퀘스트 수락",
                            style: .primary, action: action)
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(play.title). \(play.placeName). \(play.durationText). "
            + "난이도 별 \(play.difficultyStars)개. \(play.objective)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: PixelSpacing.s) {
            Text(play.title)
                .font(PixelFont.sectionTitle)
                .foregroundStyle(PixelColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: PixelSpacing.xs) {
                PixelIcon(.clock, size: 14, color: PixelColor.inkWeak)
                Text(play.durationText)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
            }
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var cover: some View {
        CoverImage(url: play.thumbnail, dimmed: false)
    }
}

// MARK: - 준비 중 카드

/// 아직 PLAY 가 없는 곳.
///
/// 활성 카드와 **같은 뼈대**에 사진을 흑백으로 낮추고 자물쇠를 얹는다.
/// 색만으로 구분하지 않는다 — 자물쇠·회색 별·비활성 버튼이 같이 말한다.
struct PreparingPlaceCard: View {
    let placeName: String
    let thumbnail: String?
    let action: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                CoverImage(url: thumbnail, dimmed: true)
                VStack(alignment: .leading, spacing: PixelSpacing.s) {
                    HStack(alignment: .firstTextBaseline, spacing: PixelSpacing.s) {
                        Text(placeName)
                            .font(PixelFont.sectionTitle)
                            .foregroundStyle(PixelColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("준비 중")
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.inkWeak)
                    }
                    // 별은 회색으로 다 비워 둔다 — 아직 난이도를 정하지 않았다.
                    StarRating(filled: 0)
                    Text("준비 중인 퀘스트입니다.")
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                }
                Button(action: action) {
                    Text("준비 중")
                        .font(PixelFont.label)
                        .foregroundStyle(PixelColor.outline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PixelSpacing.m)
                        .background(PixelColor.surfaceVariant)
                        .pixelBorder()
                }
                .buttonStyle(.plain)
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(placeName). 퀘스트 준비 중. 장소 정보를 봅니다.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

// MARK: - 부품

/// 카드 커버.
///
/// ⚠️ 지금은 KTO 실사 사진이다. **픽셀 커버로 바꾸기로 했지만**(2026-09-02)
/// 아직 그림 파일이 없다. 시안에서 뽑아 넣으면 여기만 바뀐다.
private struct CoverImage: View {
    let url: String?
    /// 준비 중이면 흑백으로 낮추고 자물쇠를 얹는다.
    let dimmed: Bool

    var body: some View {
        ZStack {
            PixelColor.surfaceDim
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
                    default: PixelColor.surfaceDim
                    }
                }
            } else {
                PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipped()
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.5 : 1)
        .overlay {
            if dimmed { PixelIcon(.lock, size: 36, color: PixelColor.ink) }
        }
        .pixelBorder(width: PixelSpacing.border)
        .pixelShadow(PixelSpacing.shadowSmall)
        .accessibilityHidden(true)
    }
}

/// 난이도 별 다섯 개.
///
/// 5단계 척도는 **콘텐츠를 만들면서 PLAY 끼리 견줘 정한다**(2026-09-02 결정).
/// 지금은 성읍(별 2) 하나뿐이라 기준점이 없다.
///
/// 시안의 별색은 `#F2B233` 인데 **우리 팔레트에 없다.** 팔레트는
/// `tests/test_design_tokens.py` 가 정확히 고정하고 있어서 새 색을 넣을 수 없다.
/// 가장 가까운 역할색인 `accent`(#D9AF00)를 쓴다.
struct StarRating: View {
    let filled: Int
    var total: Int = 5

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            ForEach(0..<total, id: \.self) { i in
                PixelIcon(.star, size: 14,
                          color: i < filled ? PixelColor.accent
                                            : PixelColor.outlineVariant)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filled > 0 ? "난이도 별 \(filled)개" : "난이도 미정")
    }
}
