import SwiftUI

/// 「가이드 투어와 무엇이 다른가요?」 — PLAY 상세 맨 아래.
///
/// ## 왜 여기 있나
///
/// `CLAUDE.md` 는 "전문 가이드의 역할을 개인의 속도에 맞는 게임형 경험으로
/// 바꾼다"고 적어놨는데, 앱 어디에도 **그 질문에 답하는 자리가 없었다.**
/// 레퍼런스(Questo)는 이 표를 **시작을 망설이는 사람이 마지막으로 보는 자리**에 뒀다.
///
/// ## 왜 표가 아니라 카드로 쌓나
///
/// 레퍼런스는 `특징 | 가이드투어 | Questo` 3열 표다. 데스크톱에서는 읽히지만
/// 아이폰 폭에서 3열을 밀어 넣으면 글자가 두세 자마다 줄바꿈된다.
/// 그래서 **한 줄을 카드 하나로 세우고 두 쪽을 위아래로** 놓는다.
/// 비교 대상이 바로 붙어 있어 대조는 그대로 살아난다.
///
/// ## 색만으로 구분하지 않는다
///
/// 왼쪽(가이드 투어)은 회색 + 흐린 아이콘, 오른쪽(놀멍봅서)은 초록 + 진한 아이콘에
/// **더해서** 각 줄 앞에 이름표를 붙인다 (DESIGN.md §7).
struct GuideComparisonSection: View {
    let comparison: GuideComparison

    var body: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.m) {
            PixelSectionHeader(title: comparison.title, icon: .shuffle,
                               accent: PixelColor.secondary)

            ForEach(comparison.rows) { row in
                PixelCard {
                    VStack(alignment: .leading, spacing: PixelSpacing.s) {
                        Text(row.aspect)
                            .font(PixelFont.label)
                            .foregroundStyle(PixelColor.ink)

                        side(label: comparison.leftLabel,
                             text: row.left, icon: row.leftIcon, ours: false)
                        side(label: comparison.rightLabel,
                             text: row.right, icon: row.rightIcon, ours: true)

                        // 숫자를 쓴 줄에는 근거를 같이 보여준다.
                        // 출처 없는 수치를 화면에 적지 않기로 했다.
                        if !row.source.isEmpty {
                            Text("출처: \(row.source)")
                                .font(PixelFont.labelSmall)
                                .foregroundStyle(PixelColor.inkWeak)
                        }
                    }
                    .padding(PixelSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(row.aspect). \(comparison.leftLabel)는 \(row.left). "
                    + "\(comparison.rightLabel)는 \(row.right).")
            }
        }
    }

    @ViewBuilder
    private func side(label: String, text: String, icon: String, ours: Bool) -> some View {
        HStack(alignment: .top, spacing: PixelSpacing.s) {
            PixelIcon(glyph(icon), size: 16,
                      color: ours ? PixelColor.primary : PixelColor.inkWeak)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(PixelFont.labelSmall)
                    .foregroundStyle(PixelColor.inkWeak)
                Text(text)
                    .font(PixelFont.body)
                    .foregroundStyle(ours ? PixelColor.ink : PixelColor.inkWeak)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(PixelSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ours ? PixelColor.surfaceHigh : PixelColor.surfaceLow)
    }

    /// 원고가 적은 아이콘 이름을 도트 아이콘으로 옮긴다.
    /// ⚠️ 모르는 이름이면 조용히 사라지지 않게 물음표 대신 기본 아이콘을 준다.
    private func glyph(_ name: String) -> PixelIcon.Glyph {
        switch name {
        case "clock":     return .clock
        case "play":      return .play
        case "person":    return .person
        case "calendar":  return .calendar
        case "check":     return .check
        case "headphone": return .headphone
        case "target":    return .target
        case "coin":      return .coin
        case "map":       return .map
        case "lock":      return .lock
        default:          return .more
        }
    }
}
