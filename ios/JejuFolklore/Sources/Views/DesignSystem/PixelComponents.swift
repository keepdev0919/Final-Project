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

extension View {
    func pixelShadow(isPressed: Bool = false) -> some View {
        modifier(PixelShadow(isPressed: isPressed))
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
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(PixelColor.surface)
            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThick)
            .pixelShadow()
    }
}

// MARK: - 배지

struct PixelBadge: View {
    enum Kind {
        case free    // 앞부분 무료
        case here    // 지금 여기예요
        case heard   // 들었어요
        case locked  // 잠김

        var fill: Color {
            switch self {
            case .free:   return PixelColor.accent
            case .here:   return PixelColor.primary
            case .heard:  return PixelColor.done
            case .locked: return PixelColor.locked
            }
        }

        /// DESIGN.md §6 — 밝은 배경(강조·완료·잠김) 위 글자는 모드 무관 어두운색으로 고정한다.
        /// 다크 모드 잉크를 강조색 위에 올리면 1.26:1이 되어 글자가 사라진다.
        /// 주색만 어두운 계열이라 표면색 글자를 쓴다.
        var label: Color {
            switch self {
            case .here: return PixelColor.surface
            default:    return PixelColor.inkFixedDark
            }
        }

        /// 색만으로 상태를 구분하지 않는다 (DESIGN.md §2).
        var icon: PixelIcon.Glyph? {
            switch self {
            case .free:   return nil
            case .here:   return .mapPin
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
                    .frame(height: PixelSpacing.m)
                    .pixelBorder(PixelColor.ink, width: PixelSpacing.borderThin)
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
