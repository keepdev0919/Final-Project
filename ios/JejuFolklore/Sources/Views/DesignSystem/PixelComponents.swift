import SwiftUI

// MARK: - 어긋난 단색 그림자 (DESIGN.md §5)

/// 번지는 그림자를 쓰지 않는다. 잉크색 사각형을 +3/+3 어긋나게 깐다.
struct PixelShadow: ViewModifier {
    var isPressed: Bool = false

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                if !isPressed {
                    PixelColor.ink
                        .offset(x: PixelSpacing.shadowOffset, y: PixelSpacing.shadowOffset)
                }
            }
            // 눌리면 그림자가 사라지고 본체가 그만큼 내려간다.
            .offset(
                x: isPressed ? PixelSpacing.shadowOffset : 0,
                y: isPressed ? PixelSpacing.shadowOffset : 0
            )
    }
}

/// 박스 네 귀퉁이에 잉크 사각형을 박는다. RPG 상자의 인상을 만드는 장치다.
///
/// 테두리만 있으면 웹 카드처럼 보인다. 귀퉁이에 점을 찍으면 "게임 UI 프레임"이 된다.
/// 크기는 테두리의 2배(8px)이고 테두리 위로 절반씩 걸치게 놓는다.
struct PixelCorners: ViewModifier {
    /// 점을 테두리 밖으로 절반 빼낸 거리.
    /// ⚠️ 안쪽에 두면 잉크 테두리 위에 잉크 점이 놓여 **아예 안 보인다**
    /// (2026-08-20에 실제로 겪음). 밖으로 빼야 귀퉁이가 튀어나온 모양이 된다.
    private var out: CGFloat { PixelSpacing.cornerAccent / 2 }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading)     { dot.offset(x: -out, y: -out) }
            .overlay(alignment: .topTrailing)    { dot.offset(x:  out, y: -out) }
            .overlay(alignment: .bottomLeading)  { dot.offset(x: -out, y:  out) }
            .overlay(alignment: .bottomTrailing) { dot.offset(x:  out, y:  out) }
    }

    private var dot: some View {
        PixelColor.ink
            .frame(width: PixelSpacing.cornerAccent, height: PixelSpacing.cornerAccent)
    }
}

extension View {
    func pixelShadow(isPressed: Bool = false) -> some View {
        modifier(PixelShadow(isPressed: isPressed))
    }

    /// 네 귀퉁이 잉크 사각형. 카드·시트처럼 큰 박스에만 쓴다.
    /// 배지나 작은 버튼에 붙이면 지저분해진다.
    func pixelCorners() -> some View {
        modifier(PixelCorners())
    }

    /// 반경 0 테두리. DESIGN.md §5 — 둥근 모서리는 픽셀아트를 즉시 깨뜨린다.
    func pixelBorder(
        _ color: Color = PixelColor.ink,
        width: CGFloat = PixelSpacing.borderThin
    ) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: width))
    }
}

// MARK: - 버튼

struct PixelButton: View {
    enum Style {
        case primary   // 주요 동작
        case accent    // CTA
        case plain     // 보조

        var fill: Color {
            switch self {
            case .primary: return PixelColor.primary
            case .accent:  return PixelColor.accent
            case .plain:   return PixelColor.surface
            }
        }

        var label: Color {
            switch self {
            case .primary: return PixelColor.surface
            case .accent:  return PixelColor.inkFixedDark
            case .plain:   return PixelColor.ink
            }
        }
    }

    let title: String
    var style: Style = .primary
    var leadingIcon: PixelIcon.Glyph? = nil
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PixelSpacing.s) {
                if let leadingIcon {
                    PixelIcon(leadingIcon, size: 24, color: style.label)
                }
                Text(title)
                    .pixelFont(PixelFont.button)
                    .foregroundStyle(style.label)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PixelSpacing.buttonHeight)
            .background(style.fill)
            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThin)
            .pixelShadow(isPressed: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - 카드

struct PixelCard<Content: View>: View {
    /// 귀퉁이 악센트를 붙일지. 큰 카드에는 붙이고, 목록 안의 작은 행에는 끈다.
    var corners: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(PixelColor.surface)
            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)
            .modifier(OptionalCorners(on: corners))
            .pixelShadow()
    }
}

private struct OptionalCorners: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.pixelCorners() } else { content }
    }
}

// MARK: - 연속 막대 (난이도처럼 정도를 나타낼 때)

/// 칸으로 나뉜 `PixelProgressBar`와 용도가 다르다.
///
/// - `PixelProgressBar` — **셀 수 있는 것**. 이야기 5개 중 3개 들음 → 칸 5개
/// - `PixelMeter`       — **정도**. 난이도, 하루 이동거리 → 채워지는 막대 하나
///
/// 셀 수 있는 걸 막대로 그리면 몇 개 남았는지 안 보이고, 정도를 칸으로 그리면
/// 없는 눈금을 만들어낸다.
struct PixelMeter: View {
    /// 0.0 ~ 1.0
    let value: Double
    var fill: Color = PixelColor.primary
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                PixelColor.background
                fill.frame(width: max(0, min(1, value)) * geo.size.width)
                    .overlay(alignment: .trailing) {
                        // 채운 끝을 잉크로 끊어 준다 — 게임 체력바의 그 인상.
                        PixelColor.ink.frame(width: PixelSpacing.borderThick)
                    }
            }
        }
        .frame(height: height)
        .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100))퍼센트")
    }
}

// MARK: - 배지

struct PixelBadge: View {
    enum Kind {
        case free    // 앞부분 무료
        case here    // 지금 여기예요
        case audio   // 해설 3분 7초 — 들을 게 있다
        case heard   // 들었어요 (다 들은 뒤)
        case locked  // 잠김

        var fill: Color {
            switch self {
            case .free:   return PixelColor.accent
            case .here:   return PixelColor.primary
            case .audio:  return PixelColor.surface
            case .heard:  return PixelColor.done
            case .locked: return PixelColor.locked
            }
        }

        /// DESIGN.md §6 — 밝은 배경(강조·완료·잠김) 위 글자는 모드 무관 어두운색으로 고정한다.
        /// 다크 모드 잉크를 강조색 위에 올리면 1.26:1이 되어 글자가 사라진다.
        /// 주색만 어두운 계열이라 표면색 글자를 쓴다.
        var label: Color {
            switch self {
            case .here:  return PixelColor.surface
            case .audio: return PixelColor.ink   // 흰 배경이라 일반 잉크
            default:     return PixelColor.inkFixedDark
            }
        }

        /// 색만으로 상태를 구분하지 않는다 (DESIGN.md §2).
        var icon: PixelIcon.Glyph? {
            switch self {
            case .free:   return nil
            case .here:   return .mapPin
            case .audio:  return .play    // "들을 게 있다" — 체크(✔)는 다 들었다는 뜻이라 틀린다
            case .heard:  return .check
            case .locked: return .lock
            }
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            if let icon = kind.icon {
                PixelIcon(icon, size: 16, color: kind.label)
            }
            Text(text)
                .pixelFont(PixelFont.badge)
                .foregroundStyle(kind.label)
        }
        .padding(.horizontal, PixelSpacing.s)
        .padding(.vertical, PixelSpacing.xs)
        .background(kind.fill)
        .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThin)
    }
}

// MARK: - 진행바 (DESIGN.md §6 — 칸으로 나뉜 막대)

struct PixelProgressBar: View {
    let total: Int
    let filled: Int

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? PixelColor.done : Color.clear)
                    // 테두리가 4px이라 칸 높이가 12px이면 안이 안 보인다.
                    .frame(height: PixelSpacing.xl)
                    .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("이야기 \(total)개 중 \(filled)개 들음")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: PixelSpacing.xl) {
            PixelButton(title: "이야기 시작", style: .primary) {}
            PixelButton(title: "미리 받아두기", style: .accent, leadingIcon: .download) {}
            PixelButton(title: "미리 듣기", style: .plain) {}

            HStack(spacing: PixelSpacing.s) {
                PixelBadge(text: "앞부분 무료", kind: .free)
                PixelBadge(text: "지금 여기예요", kind: .here)
            }
            HStack(spacing: PixelSpacing.s) {
                PixelBadge(text: "들었어요", kind: .heard)
                PixelBadge(text: "잠김", kind: .locked)
            }

            PixelProgressBar(total: 5, filled: 3)

            PixelCard {
                VStack(alignment: .leading, spacing: PixelSpacing.s) {
                    Text("성산일출봉")
                        .pixelFont(PixelFont.cardTitle)
                        .foregroundStyle(PixelColor.ink)
                    Text("아름다움 뒤의 이야기")
                        .pixelFont(PixelFont.badge)
                        .foregroundStyle(PixelColor.inkWeak)
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(PixelSpacing.l)
    }
    .background(PixelColor.background)
}
