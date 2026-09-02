import SwiftUI

// MARK: - 그림자

/// 어긋난 단색 그림자. 번지지 않는다(blur 0).
///
/// **테두리는 2px로 얇고 그림자는 4~8px로 크다.** 그 대비가 "종이가 떠 있는" 인상을 만든다.
/// 둘 다 4px로 두면 뭉툭해진다(2026-08-20에 실제로 겪음).
struct PixelShadow: ViewModifier {
    var offset: CGFloat = PixelSpacing.shadowCard
    /// 버튼은 아래로만 그림자를 던진다 — 눌리는 물건이라 옆으로 밀리면 안 된다.
    var downOnly: Bool = false
    var isPressed: Bool = false

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                if !isPressed {
                    PixelColor.ink.offset(x: downOnly ? 0 : offset, y: offset)
                }
            }
            .offset(x: isPressed && !downOnly ? offset : 0,
                    y: isPressed ? offset : 0)
    }
}

/// 큰 상자 귀퉁이의 8×8 잉크 사각형. RPG 상자 인상을 만드는 장치다.
///
/// ⚠️ 테두리 **밖으로** 빼야 한다. 안쪽에 두면 잉크 테두리 위 잉크 점이라 안 보인다.
struct PixelCorners: ViewModifier {
    private var out: CGFloat { PixelSpacing.cornerAccentOut }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading)     { dot.offset(x: -out, y: -out) }
            .overlay(alignment: .topTrailing)    { dot.offset(x:  out, y: -out) }
            .overlay(alignment: .bottomLeading)  { dot.offset(x: -out, y:  out) }
            .overlay(alignment: .bottomTrailing) { dot.offset(x:  out, y:  out) }
    }

    private var dot: some View {
        PixelColor.ink.frame(width: PixelSpacing.cornerAccent,
                             height: PixelSpacing.cornerAccent)
    }
}

extension View {
    func pixelShadow(_ offset: CGFloat = PixelSpacing.shadowCard,
                     downOnly: Bool = false, isPressed: Bool = false) -> some View {
        modifier(PixelShadow(offset: offset, downOnly: downOnly, isPressed: isPressed))
    }

    func pixelCorners() -> some View { modifier(PixelCorners()) }

    /// 반경 0 테두리. 기본 2px.
    func pixelBorder(_ color: Color = PixelColor.ink,
                     width: CGFloat = PixelSpacing.border) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: width))
    }

    /// 이중 테두리 — 겉 4px + 안쪽 4px 띄워 2px. **화면에서 가장 중요한 상자 하나에만.**
    func pixelDoubleBorder() -> some View {
        self
            .overlay(
                Rectangle()
                    .strokeBorder(PixelColor.ink, lineWidth: PixelSpacing.border)
                    .padding(PixelSpacing.xs)
            )
            .pixelBorder(PixelColor.ink, width: PixelSpacing.borderHeavy)
    }
}

// MARK: - 섹션 헤더 (시안의 가장 특징적인 패턴)

/// 아이콘 + 제목 + 하단 2px 밑줄. 카드마다 반복되면서 "일지" 인상을 만든다.
struct PixelSectionHeader<Trailing: View>: View {
    let title: String
    var icon: PixelIcon.Glyph? = nil
    var accent: Color = PixelColor.ink
    /// 제목 줄 오른쪽에 붙는 것 ("총 12명" 같은 곁수치).
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PixelSpacing.s) {
                if let icon { PixelIcon(icon, size: 24, color: accent) }
                Text(title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.bottom, PixelSpacing.s)
            Rectangle()
                .fill(accent)
                .frame(height: PixelSpacing.border)
        }
    }
}

extension PixelSectionHeader where Trailing == EmptyView {
    init(title: String, icon: PixelIcon.Glyph? = nil, accent: Color = PixelColor.ink) {
        self.init(title: title, icon: icon, accent: accent) { EmptyView() }
    }
}

// MARK: - 버튼

struct PixelButton: View {
    enum Style {
        case primary, accent, plain

        var fill: Color {
            switch self {
            case .primary: return PixelColor.primary
            case .accent:  return PixelColor.accent
            case .plain:   return PixelColor.surface
            }
        }
        var label: Color {
            switch self {
            case .primary: return PixelColor.onPrimary
            case .accent:  return PixelColor.onAccent
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
                    .font(PixelFont.label)
                    .foregroundStyle(style.label)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PixelSpacing.buttonHeight)
            .background(style.fill)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowButton, downOnly: true, isPressed: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - 버튼 스타일 (레이블을 직접 만든 Button에)

/// `PixelButton`은 제목 문자열을 받는다. 레이블을 직접 그린 `Button`에는 이걸 쓴다.
///
/// 시스템 `.bordered`·`.borderedProminent`를 대신한다 — 그것들은 둥근 모서리라
/// 시안과 어긋난다("모서리를 굴리지 않는다").
struct PixelButtonStyle: ButtonStyle {
    var kind: PixelButton.Style = .primary

    init(_ kind: PixelButton.Style = .primary) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelFont.label)
            .foregroundStyle(kind.label)
            .padding(.horizontal, PixelSpacing.l)
            .padding(.vertical, PixelSpacing.m)
            .background(kind.fill)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowButton,
                         downOnly: true, isPressed: configuration.isPressed)
    }
}

// MARK: - 카드

struct PixelCard<Content: View>: View {
    var corners: Bool = true
    /// 강조 상자는 그림자를 8px로 키운다 (대화상자·히어로).
    var strong: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(PixelColor.surface)
            .pixelBorder()
            .modifier(OptionalCorners(on: corners))
            .pixelShadow(strong ? PixelSpacing.shadowStrong : PixelSpacing.shadowCard)
    }
}

private struct OptionalCorners: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.pixelCorners() } else { content }
    }
}

// MARK: - 칩 (작은 태그)

/// `제주도` `하이킹` `2-3시간` 처럼 가로로 나열한다.
struct PixelChip: View {
    let text: String
    var icon: PixelIcon.Glyph? = nil
    var fill: Color = PixelColor.surface
    var label: Color = PixelColor.ink

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            if let icon { PixelIcon(icon, size: 16, color: label) }
            Text(text).font(PixelFont.label).foregroundStyle(label)
        }
        .padding(.horizontal, PixelSpacing.m)
        .padding(.vertical, 6)
        .background(fill)
        .pixelBorder()
        .pixelShadow(PixelSpacing.shadowSmall)
    }
}

// MARK: - 등급 배지 (카드 밖으로 튀어나온 스티커)

/// 3도 기울임이 스티커 느낌을 만든다. **카드마다 붙이지 않는다** — 특별한 것 하나에만.
struct PixelStickerBadge: View {
    let text: String
    var fill: Color = PixelColor.accent

    var body: some View {
        Text(text)
            .font(PixelFont.label)
            .foregroundStyle(PixelColor.onAccent)
            .padding(.horizontal, PixelSpacing.s)
            .padding(.vertical, PixelSpacing.xs)
            .background(fill)
            .pixelBorder()
            .pixelShadow(PixelSpacing.shadowSmall)
            .rotationEffect(.degrees(3))
    }
}

// MARK: - 상태 배지

struct PixelBadge: View {
    enum Kind {
        case free, here, audio, heard, locked

        var fill: Color {
            switch self {
            case .free:   return PixelColor.accent
            case .here:   return PixelColor.primary
            case .audio:  return PixelColor.surface
            case .heard:  return PixelColor.done
            case .locked: return PixelColor.locked
            }
        }
        /// 채움색마다 짝이 되는 글자색을 쓴다. 모드에 따라 갈린다 — §2 참조.
        var label: Color {
            switch self {
            case .free:   return PixelColor.onAccent
            case .here:   return PixelColor.onPrimary
            case .audio:  return PixelColor.ink      // 표면(흰) 배경
            case .heard:  return PixelColor.onDone
            case .locked: return PixelColor.onLocked
            }
        }
        /// 색만으로 상태를 구분하지 않는다.
        var icon: PixelIcon.Glyph? {
            switch self {
            case .free:   return nil
            case .here:   return .mapPin
            case .audio:  return .play    // 체크(✔)는 "다 들었다"는 뜻이라 틀린다
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
            Text(text).font(PixelFont.labelSmall).foregroundStyle(kind.label)
        }
        .padding(.horizontal, PixelSpacing.s)
        .padding(.vertical, PixelSpacing.xs)
        .background(kind.fill)
        .pixelBorder()
        .pixelShadow(PixelSpacing.shadowSmall)
    }
}

// MARK: - 막대 ① 채워지는 막대 (정도)

/// 난이도·이동거리·진행률처럼 **정도**를 나타낸다. 배경은 잉크, 안에 숫자를 넣는다.
///
/// 셀 수 있는 것(이야기 5개 중 3개)에는 `PixelProgressBar`를 쓴다. 섞으면 둘 다 거짓말이 된다.
struct PixelMeter: View {
    /// 0.0 ~ 1.0
    let value: Double
    var fill: Color = PixelColor.primary
    /// 막대 안에 넣을 글자. 비우면 안 그린다.
    var caption: String? = nil
    var height: CGFloat = 32

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    PixelColor.ink
                    fill.frame(width: max(0, min(1, value)) * geo.size.width)
                }
            }
            if let caption {
                Text(caption)
                    .font(PixelFont.label)
                    .foregroundStyle(.white)
                    .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            }
        }
        .frame(height: height)
        .pixelBorder()
        .accessibilityElement()
        .accessibilityValue(caption ?? "\(Int(value * 100))퍼센트")
    }
}

// MARK: - 막대 ② 칸으로 나뉜 막대 (셀 수 있는 것)

struct PixelProgressBar: View {
    let total: Int
    let filled: Int

    var body: some View {
        HStack(spacing: PixelSpacing.xs) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    // `done`(=primaryContainer)은 다크에서 어두운 초록(#005229)이라
                    // 어두운 배경 위 빈 칸과 거의 구분되지 않았다. `primary`는 다크에서
                    // 밝은 초록(#51E088)이라 두 모드 모두 채운 칸이 또렷하다.
                    .fill(index < filled ? PixelColor.primary : Color.clear)
                    .frame(height: PixelSpacing.xl)
                    .pixelBorder()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(total)개 중 \(filled)개")
    }
}
