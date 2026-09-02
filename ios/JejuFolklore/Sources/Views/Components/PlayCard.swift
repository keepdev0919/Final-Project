import SwiftUI

/// 홈의 PLAY 카드.
///
/// 장소를 설명하지 않는다. **여기서 무슨 게임을 하게 되는지**를 보여준다.
/// 그래서 제목이 장소명이 아니라 PLAY 제목이고, 장소명은 그 아래 작게 붙는다.
///
/// 담는 것 (`콘텐츠.md` §5 · `레퍼런스.md` §7):
///
///     [실사 사진]
///     성읍 생활기록 복원작전     ← PLAY 제목
///     성읍민속마을              ← 장소명
///     60~75분 · 약 1km · 쉬움
///     8 Missions
///     네 채의 옛집을 조사해…     ← 한 줄 목표
///
/// 시간·거리·난이도·Mission 수를 시작 전에 보여주는 것은 레퍼런스에서 가져온
/// 규칙이다. 얼마나 걷고 얼마나 걸리는지 모르면 현장에서 시작을 못 누른다.
struct PlayCard: View {
    let play: PlaySummary
    /// 진행 중이면 「생활기록 4 / 6」처럼 표시한다. 없으면 안 뜬다.
    var progressText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelCard {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    photo
                    Text(play.title)
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(play.placeName)
                        .font(PixelFont.labelSmall)
                        .foregroundStyle(PixelColor.inkWeak)
                    metaRow
                    if !play.objective.isEmpty {
                        Text(play.objective)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.inkWeak)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(play.title). \(play.placeName). "
            + "\(play.durationText), \(play.distanceText), 난이도 \(play.difficulty), "
            + "미션 \(play.missionCount)개. \(play.objective)"
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 사진

    @ViewBuilder
    private var photo: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let urlString = play.thumbnail, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
                    default: PixelColor.surfaceHigh
                    }
                }
            } else {
                PixelIcon(.photo, size: 40, color: PixelColor.inkWeak)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) { statusStamp }
        .pixelBorder()
        .accessibilityHidden(true)
    }

    /// 진행 상태 도장. 안 한 것과 하다 만 것이 눈에 확 다르게.
    private var statusStamp: some View {
        Text(progressText ?? "PLAY")
            .font(PixelFont.label)
            .foregroundStyle(progressText == nil ? PixelColor.onAccent : PixelColor.onPrimary)
            .padding(.horizontal, PixelSpacing.s)
            .padding(.vertical, PixelSpacing.xs)
            .background(progressText == nil ? PixelColor.accent : PixelColor.primary)
            .pixelBorder()
            .rotationEffect(.degrees(-3))
            .padding(PixelSpacing.s)
    }

    // MARK: - 메타

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.xs) {
            HStack(spacing: PixelSpacing.s) {
                metaItem(.clock, play.durationText)
                metaItem(.map, play.distanceText)
                metaItem(.target, play.difficulty)
            }
            Text("\(play.missionCount) Missions")
                .font(PixelFont.label)
                .foregroundStyle(PixelColor.ink)
        }
    }

    private func metaItem(_ icon: PixelIcon.Glyph, _ text: String) -> some View {
        HStack(spacing: PixelSpacing.xs) {
            PixelIcon(icon, size: 14, color: PixelColor.inkWeak)
            Text(text)
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
    }
}

// MARK: - 준비 중 카드

/// 아직 PLAY 가 없는 곳. **눌러도 게임이 없다는 것을 카드가 미리 말해준다.**
///
/// 활성 카드와 색만 다르게 하지 않는다 — 도장 글자와 사진 유무로도 구분된다
/// (DESIGN.md §7 접근성).
struct PreparingPlaceCard: View {
    let placeName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelCard {
                HStack(spacing: PixelSpacing.m) {
                    PixelIcon(.lock, size: 24, color: PixelColor.inkWeak)
                    VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                        Text(placeName)
                            .font(PixelFont.body)
                            .foregroundStyle(PixelColor.ink)
                        Text("PLAY 준비 중")
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.inkWeak)
                    }
                    Spacer(minLength: 0)
                    PixelIcon(.forward, size: 16, color: PixelColor.inkWeak)
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(placeName). PLAY 준비 중. 장소 정보를 봅니다.")
        .accessibilityAddTraits(.isButton)
    }
}
