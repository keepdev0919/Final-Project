import SwiftUI
import UIKit

/// 퀘스트 카드.
///
/// **시안 HTML 을 1:1로 옮긴 것이다.** 크기를 우리 토큰 이름으로 "번역"하지 않고
/// 시안에 적힌 px 를 그대로 쓴다 — 한 번 그렇게 했다가 제목이 14 대신 24가 되어
/// 카드가 부풀었고, 한 화면에 세 장 들어갈 것이 한 장만 들어갔다(2026-09-02).
///
///     div.bg-surface.pixel-border.p-4.flex.flex-col.gap-4
///       div.h-40.pixel-border-sm                     커버 160
///       div
///         h4.font-label-lg           14 / w700       제목
///         div.font-label-sm          12 / w500       🕐 60-75분  🚶 1km
///         ★★☆☆☆                     14
///         p.text-body-sm             14 / line-clamp-2
///       button.py-2.font-label-lg    14 / w700       퀘스트 수락
struct PlayCard: View {
    let play: PlaySummary
    /// 진행 중이면 「이어서 하기」처럼 버튼 문구가 바뀐다.
    var progressText: String? = nil
    let action: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {   // gap-4
                QuestCoverImage(coverName: play.placeKey, url: play.thumbnail, locked: false)

                VStack(alignment: .leading, spacing: 0) {
                    titleRow
                        .padding(.bottom, PixelSpacing.m)
                    StarRating(filled: play.difficultyStars)
                        .padding(.bottom, PixelSpacing.m)
                    Text(play.cardText)
                        // ⚠️ 시안의 `text-body-sm` 은 **Tailwind config 에 없는 클래스**다.
                        // 무시되고 브라우저 기본 16px 로 렌더된다. 클래스 이름을 믿고
                        // 14로 줄였다가 글자가 작아졌다(2026-09-02).
                        .font(PixelFont.body)                        // 16
                        .foregroundStyle(PixelColor.inkWeak)
                        .lineLimit(2)                                // line-clamp-2
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                QuestButton(title: progressText ?? "퀘스트 수락",
                            filled: true, action: action)
            }
            .padding(PixelSpacing.cardPadding)                       // p-4
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(play.title). \(play.placeName). \(play.durationText), \(play.distanceShort). "
            + "난이도 별 \(play.difficultyStars)개. \(play.cardText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    /// 제목 왼쪽, 시간·거리 오른쪽. 시안의 `justify-between`.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: PixelSpacing.l) {
            Text(play.title)
                .font(PixelFont.label)                               // label-lg 14 / w700
                .foregroundStyle(PixelColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: PixelSpacing.l) {                        // gap-4
                metaItem(.clock, play.durationText)
                metaItem(.walk, play.distanceShort)
            }
            .layoutPriority(1)
        }
    }

    private func metaItem(_ icon: PixelIcon.Glyph, _ text: String) -> some View {
        HStack(spacing: PixelSpacing.xs) {                           // gap-1
            PixelIcon(icon, size: 18, color: PixelColor.inkWeak)     // text-[18px]
            Text(text)
                .font(PixelFont.labelSmall)                          // label-sm 12
                .foregroundStyle(PixelColor.inkWeak)
                .fixedSize()
        }
    }
}

// MARK: - 준비 중 카드

/// 아직 퀘스트가 없는 곳.
///
/// 시안대로 **활성 카드와 같은 뼈대**에 사진만 흑백으로 낮추고 자물쇠를 얹는다.
/// 별도, 별점도, 우상단 딱지도 **없다** — 아직 정한 것이 없으니 보여줄 것도 없다.
struct PreparingPlaceCard: View {
    let placeName: String
    let coverName: String?
    let thumbnail: String?
    let action: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                QuestCoverImage(coverName: coverName, url: thumbnail, locked: true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(placeName)
                        .font(PixelFont.label)
                        .foregroundStyle(PixelColor.ink)
                        .lineLimit(1)
                        .padding(.bottom, PixelSpacing.s)
                    Text("준비 중인 퀘스트입니다.")
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                }

                QuestButton(title: "준비 중", filled: false, action: action)
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

/// 카드 커버. 시안 `div.h-40.pixel-border-sm`.
///
/// **픽셀 커버가 있으면 그것을, 없으면 KTO 실사 사진을 쓴다.**
/// 파일은 `Resources/Covers/<place_key>.png` — 시안이 만든 그림을 받아 둔 것이다.
///
/// ⚠️ 픽셀아트는 `.interpolation(.none)` 으로 그린다. 기본 보간을 쓰면 확대할 때
/// 도트가 뭉개져서 픽셀아트가 아니라 흐린 그림이 된다.
struct QuestCoverImage: View {
    /// 픽셀 커버 파일 이름 (= place_key). 번들에 없으면 사진으로 떨어진다.
    let coverName: String?
    let url: String?
    /// 준비 중이면 흑백으로 낮추고 자물쇠를 얹는다 (시안 `grayscale opacity-50`).
    let locked: Bool

    private var pixelCover: UIImage? {
        guard let coverName else { return nil }
        return UIImage(named: coverName)
    }

    var body: some View {
        ZStack {
            PixelColor.surfaceDim
            if let cover = pixelCover {
                Image(uiImage: cover)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
            } else if let url, let u = URL(string: url) {
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
        .frame(height: 160)                                      // h-40
        .frame(maxWidth: .infinity)
        .clipped()
        .grayscale(locked ? 1 : 0)
        .opacity(locked ? 0.5 : 1)
        .overlay {
            if locked {
                PixelIcon(.lock, size: 36, color: PixelColor.ink)  // text-4xl
            }
        }
        .pixelBorder(width: PixelSpacing.border)                 // 2px
        .pixelShadow(PixelSpacing.shadowSmall)                   // 2px
        .accessibilityHidden(true)
    }
}

/// 카드 맨 아래 버튼. 시안 `button.py-2.font-label-lg.pixel-border`.
///
/// `PixelButton` 을 쓰지 않는다 — 그쪽은 높이 48에 글자가 16이라 카드 안에서
/// 시안보다 두 배로 두꺼워진다.
private struct QuestButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PixelFont.label)                            // label-lg 14 / w700
                .foregroundStyle(filled ? PixelColor.onPrimary : PixelColor.outline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PixelSpacing.s)               // py-2
                .background(filled ? PixelColor.primary : PixelColor.surfaceVariant)
                .pixelBorder(width: PixelSpacing.borderHeavy)     // 4px
                .pixelShadow(PixelSpacing.shadowCard)             // 4px
        }
        .buttonStyle(.plain)
    }
}

/// 난이도 별 다섯 개. 시안 14px.
///
/// 5단계 척도는 **콘텐츠를 만들면서 PLAY 끼리 견줘 정한다**(2026-09-02 결정).
/// 시안 별색 `#F2B233` 은 우리 팔레트에 없다 —
/// `tests/test_design_tokens.py` 가 팔레트를 정확히 고정하고 있어서
/// 가장 가까운 역할색 `accent`(#D9AF00)를 쓴다.
struct StarRating: View {
    let filled: Int
    var total: Int = 5

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            ForEach(0..<total, id: \.self) { i in
                PixelIcon(.star, size: 16,
                          color: i < filled ? PixelColor.accent
                                            : PixelColor.outlineVariant)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filled > 0 ? "난이도 별 \(filled)개" : "난이도 미정")
    }
}

// MARK: - 카드가 쓰는 글

extension PlaySummary {
    /// 카드 설명. 짧은 판이 있으면 그것을, 없으면 목표 문장을 쓴다.
    var cardText: String { cardSummary.isEmpty ? objective : cardSummary }

    /// 시안은 거리를 「1km」로 쓴다 — 「약」을 붙이지 않는다.
    var distanceShort: String {
        distanceMeters < 1000
            ? "\(distanceMeters)m"
            : String(format: "%.1fkm", Double(distanceMeters) / 1000)
                .replacingOccurrences(of: ".0km", with: "km")
    }
}
