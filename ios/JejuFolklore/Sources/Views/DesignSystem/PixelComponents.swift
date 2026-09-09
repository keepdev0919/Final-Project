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

extension View {
    func pixelShadow(_ offset: CGFloat = PixelSpacing.shadowCard,
                     downOnly: Bool = false, isPressed: Bool = false) -> some View {
        modifier(PixelShadow(offset: offset, downOnly: downOnly, isPressed: isPressed))
    }

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

/// 아이콘 + 제목 + 하단 밑줄. 카드마다 반복되면서 "일지" 인상을 만든다.
///
/// 밑줄 두께가 **층을 나눈다** (2026-09-09 조익준님 결정).
///
///     2px (`border`)        카드 **안**의 작은 구획 — 기본정보·이용팁 같은 것
///     4px (`borderHeavy`)   화면을 가르는 큰 섹션 — 퀘스트 목록, 코스 탭 두 섹션
///
/// 퀘스트 탭이 4px 짜리를 자기 파일에서 따로 그리고 있었는데, 코스 탭 두 섹션이
/// 같은 모양을 쓰게 되면서 이 부품 하나로 합쳤다.
struct PixelSectionHeader<Trailing: View>: View {
    let title: String
    var icon: PixelIcon.Glyph? = nil
    var accent: Color = PixelColor.ink
    /// 아이콘만 다른 색으로 두고 싶을 때. 비우면 `accent` 를 따른다 —
    /// 시안의 큰 섹션은 **아이콘만 색이고 제목·밑줄은 잉크**다.
    var iconColor: Color? = nil
    var underline: CGFloat = PixelSpacing.border
    /// 제목 줄 오른쪽에 붙는 것 ("총 12명" 같은 곁수치, 「다른 코스」 같은 버튼).
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PixelSpacing.s) {
                if let icon { PixelIcon(icon, size: 24, color: iconColor ?? accent) }
                Text(title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(accent)
                Spacer(minLength: PixelSpacing.s)
                trailing
            }
            .padding(.bottom, PixelSpacing.s)
            Rectangle()
                .fill(accent)
                .frame(height: underline)
        }
    }
}

extension PixelSectionHeader where Trailing == EmptyView {
    init(title: String,
         icon: PixelIcon.Glyph? = nil,
         accent: Color = PixelColor.ink,
         iconColor: Color? = nil,
         underline: CGFloat = PixelSpacing.border) {
        self.init(title: title, icon: icon, accent: accent,
                  iconColor: iconColor, underline: underline) { EmptyView() }
    }
}

// MARK: - 통통 (제자리에서 떠다니기)

/// 화면에 뜬 채로 **계속 위아래로 통통 떠다닌다** (2026-09-09 조익준님 결정).
///
/// 누를 때 반응하는 게 아니라 **가만히 있어도 움직인다**. 게임 화면의 지도 표식이
/// 그렇듯, 이게 있어야 「고르는 판」이 정지 그림이 아니라 살아 있는 것으로 보인다.
///
/// `delay` 로 표식마다 시작을 어긋나게 한다. 넷이 한 몸처럼 같이 오르내리면
/// 살아 있다기보다 화면 전체가 흔들리는 것처럼 보인다.
struct PixelBob: ViewModifier {
    /// 위아래 진폭(pt). 크면 멀미 난다 — 3pt 안팎이 「떠 있다」로 읽히는 선이다.
    var distance: CGFloat = 3
    /// 한 번 오르내리는 데 걸리는 시간(초).
    var period: Double = 1.8
    /// 표식마다 어긋나게 시작하는 시간(초).
    var delay: Double = 0

    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -distance : distance)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: period / 2)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) { up = true }
            }
    }
}

extension View {
    func pixelBob(delay: Double = 0,
                  distance: CGFloat = 3,
                  period: Double = 1.8) -> some View {
        modifier(PixelBob(distance: distance, period: period, delay: delay))
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
    /// 강조 상자는 그림자를 8px로 키운다 (대화상자·히어로).
    var strong: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(PixelColor.surface)
            // 시안의 `.pixel-border` — 4px 테두리 + 4px 그림자. 그게 전부다.
            //
            // ⚠️ 2026-09-03: 귀퉁이 8pt 잉크 점(`PixelCorners`)을 걷어냈다.
            // 시안 CSS 에 `dialogue-corner` 라는 4px 점 장식이 있긴 하다. 그런데
            // `position: absolute` 의 기준은 **패딩 상자**라서 `top:-4px; left:-4px`
            // 가 4px 테두리 **위에** 정확히 얹힌다. 색까지 같으니 화면에서는
            // 좌상단도 우하단도 **아예 보이지 않는다** — 시안에서 이 장식은 없는 것과 같다.
            //
            // 우리가 찍던 점은 시안 것이 아니라 예전에 우리가 넣은 별개 장치였고,
            // 8pt 를 2pt 밖으로 빼서 3배 화면에서는 24픽셀 덩어리로 튀었다.
            .pixelBorder(width: PixelSpacing.borderHeavy)
            .pixelShadow(strong ? PixelSpacing.shadowStrong : PixelSpacing.shadowCard)
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

// MARK: - 떠 있는 뒤로가기 버튼

/// 시스템 상단바를 걷어내고 왼쪽 위에 **픽셀 버튼**을 얹는다
/// (2026-09-03 조익준님 결정).
///
/// **왜.** 시스템 상단바는 회색 띠 + 시스템 서체 + 둥근 화살표로 되어 있어
/// 이 앱에서 혼자 이질적이다. 게임 화면의 HUD 버튼처럼 그림 위에 작게 띄운다.
///
/// **높이를 먹지 않는다.** 버튼을 위해 줄을 따로 만들면 상단바를 없애서 아낀
/// 44pt 를 그대로 다시 쓴다. 그래서 내용 **위에 겹쳐** 놓는다.
///
/// ⚠️ `navigationBarBackButtonHidden` 을 쓰지 않는다 — 그걸 쓰면 화면을 옆으로
/// 밀어 뒤로 가는 제스처가 함께 죽는다. 상단바만 숨긴다.
struct PixelFloatingBack: ViewModifier {
    /// 버튼이 그림 위에 얹히도록 위에서 얼마나 내릴지. 화면마다 내용이 시작하는
    /// 높이가 달라서 호출부가 정한다.
    var topInset: CGFloat = PixelSpacing.s
    /// 왼쪽에서 얼마나 들일지. 카드 안쪽에서 시작하는 화면은 더 들여야 한다.
    var leadingInset: CGFloat = PixelSpacing.xl

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    PixelIcon(.back, size: 20, color: PixelColor.ink)
                        .frame(width: 36, height: 36)
                        .background(PixelColor.surface)
                        .pixelBorder(width: PixelSpacing.border)
                        .pixelShadow(PixelSpacing.shadowSmall)
                }
                .buttonStyle(.plain)
                .padding(.leading, leadingInset)
                .padding(.top, topInset)
                .accessibilityLabel("뒤로")
            }
    }
}

extension View {
    func pixelFloatingBack(topInset: CGFloat = PixelSpacing.s,
                           leadingInset: CGFloat = PixelSpacing.xl) -> some View {
        modifier(PixelFloatingBack(topInset: topInset, leadingInset: leadingInset))
    }
}

// MARK: - 눌리는 상자 (레이블을 직접 그린 버튼·NavigationLink 에)

/// **카드가 아니라 버튼임을 형태로 말한다.**
///
///     카드   그림자를 대각선(오른쪽 아래)으로 던진다
///     버튼   그림자를 아래로만 던지고, 누르면 그림자 속으로 가라앉는다
///
/// `PixelButtonStyle` 과 달리 글자·색·여백을 건드리지 않는다 — 레이블을 이미
/// 다 그려 놓은 자리(예: PLAY 상세의 「장소 정보」 상자)에 씌우는 용도다.
struct PixelPressStyle: ButtonStyle {
    var offset: CGFloat = PixelSpacing.shadowButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pixelShadow(offset, downOnly: true, isPressed: configuration.isPressed)
    }
}

// MARK: - 깜빡이는 글자

/// 옛 게임의 「PRESS START」 처럼 **사라졌다 나타났다** 한다.
///
/// 1초 보이고 1초 사라진다 (2026-09-03 조익준님 결정).
///
/// **서서히 흐려지지 않는다.** 아예 보이거나 아예 안 보인다. 옛 게임의 깜빡임이
/// 그랬고, 픽셀 글자는 반투명해지는 순간 도트가 흐릿하게 뭉개진다.
///
/// 자리는 차지한 채 안 보이기만 하므로 **버튼 크기가 들썩이지 않는다.**
///
/// ⚠️ 설정에서 **「동작 줄이기」**를 켠 사용자에게는 깜빡이지 않는다.
struct PixelBlink: ViewModifier {
    /// 한 칸이 몇 초 머무는가.
    var frameDuration: TimeInterval = 1.0
    /// 칸마다 보이는가. 1초 보임 · 1초 사라짐.
    var visible: [Bool] = [true, false]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.periodic(from: .now, by: frameDuration)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / frameDuration)
                content
                    .opacity(visible[abs(tick) % visible.count] ? 1 : 0)
                    // 사이 값을 만들지 않는다 — 켜짐에서 꺼짐으로 바로 건너뛴다.
                    .animation(nil, value: tick)
            }
        }
    }
}

extension View {
    func pixelBlink() -> some View { modifier(PixelBlink()) }
}

// MARK: - 탭 머리말 카드

/// **이 탭이 무엇을 하는 곳인지** 화면 맨 위에서 말하는 카드.
///
/// 퀘스트·코스·지도 세 탭이 같은 것을 쓴다 (2026-09-09 조익준님 결정). 전에는 탭마다
/// 문법이 달랐다 — 퀘스트는 카드, 코스는 맨 텍스트, 지도는 숫자줄. 같은 앱으로 보이지
/// 않았다.
///
///     [잉크 블록 + 그 탭의 색 아이콘]
///     굵은 제목
///     여러 줄 설명
///
/// **색은 탭마다 다르고, 톤은 자리마다 다르다.**
/// 잉크 블록 위에는 밝은 톤(`*Container`)을, 글자 강조에는 진한 톤을 쓴다 —
/// 금색 #FFC61A 를 흰 카드 위 글자에 쓰면 대비가 1.57:1 이라 사실상 안 보인다.
struct PixelIntroCard: View {
    let icon: PixelIcon.Glyph
    /// 잉크 블록 안 아이콘 색. 그 탭을 대표하는 **밝은 톤**.
    let iconColor: Color
    /// 강조 낱말에 색을 넣을 수 있도록 `Text` 를 그대로 받는다.
    let title: Text
    let message: Text

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.l) {
                PixelIcon(icon, size: 30, color: iconColor)
                    .frame(width: 48, height: 48)
                    .background(PixelColor.ink)
                    .pixelBorder(width: PixelSpacing.border)
                    .pixelShadow(PixelSpacing.shadowSmall)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PixelSpacing.s) {
                    title
                        .font(PixelFont.sectionTitle)
                        .foregroundStyle(PixelColor.ink)
                    message
                        .font(PixelFont.bodyLarge)
                        .foregroundStyle(PixelColor.inkWeak)
                        // 시안 `leading-relaxed` = 1.625. 18 × 1.625 = 29.25 →
                        // 기본 줄높이(약 22)에 7 을 더한다.
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PixelSpacing.xxl - PixelSpacing.s)   // 24
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
