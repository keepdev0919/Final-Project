import SwiftUI

/// **화면 글자는 갈무리 픽셀 폰트로 쓴다** (2026-09-03 조익준님 결정).
///
/// ## 왜 다시 갈무리인가
///
/// 2026-08-20 에 「시안이 산세리프라서」라는 이유로 갈무리를 뺐었다. 그런데 시안이
/// 산세리프인 것은 **선택이 아니라 사고였다** — Stitch 가 불러오는 Space Grotesk 와
/// Work Sans 는 라틴 전용이라 한글 글리프가 아예 없다. 브라우저가 시스템 한글 폰트로
/// 떨어뜨린 결과를 우리가 「시안의 서체」로 읽은 것이다.
///
/// ## 크기는 시안 사다리를 유지한다
///
/// 갈무리11 은 em 이 12 라 **12·24 에서 도트가 딱 떨어지고** 나머지 크기에서는
/// iOS 가 갈아 그린다. 크기를 12·24 배수로 바꾸면 도트는 선명해지지만 시안과
/// 레이아웃이 어긋난다. 시안 사다리를 지키는 쪽을 택했다.
///
/// ## 굵기
///
/// 갈무리는 **Regular 와 Bold 두 벌뿐**이다. 시안의 w500·w600·w700 은 전부 Bold 로
/// 접는다. `.bold()` 로 굵게 만들려 하면 안 된다 — 커스텀 폰트에 없는 굵기는
/// iOS 가 획을 뭉개서 흉내 내고, 도트가 번진다.
enum PixelFont {
    private static let regular = "Galmuri11-Regular"
    private static let bold    = "Galmuri11-Bold"

    /// ⚠️ `fixedSize:` 다. `size:` 로 두면 손글씨 크기 설정을 따라 커지는데,
    /// 픽셀 폰트는 도트 격자가 어긋나 뭉개진다.
    private static func g(_ size: CGFloat, bold isBold: Bool = false) -> Font {
        .custom(isBold ? bold : regular, fixedSize: size)
    }

    /// 화면 최상단 큰 제목 — 시안 `headline-lg-mobile` 28 / w700
    static let screenTitle = g(28, bold: true)
    /// 섹션 제목 · 카드 제목 — 시안 `headline-md` 24 / w600
    static let sectionTitle = g(24, bold: true)
    /// 소개문 — 시안 `body-lg` 18 / w400
    static let bodyLarge = g(18)
    /// 소개문 안에서 낱말 하나를 강조할 때. `.bold()` 대신 이걸 쓴다.
    static let bodyLargeBold = g(18, bold: true)
    /// 본문 — 시안 `body-md` 16 / w400
    static let body = g(16)
    /// 라벨 · 버튼 · 칩 — 시안 `label-lg` 14 / w700
    static let label = g(14, bold: true)
    /// 작은 라벨 · 배지 — 시안 `label-sm` 12 / w500 → Bold 로 접는다
    static let labelSmall = g(12, bold: true)

    /// 시안 `body-sm` 은 Tailwind 설정에 **없는 클래스**라 기본 16 으로 렌더된다.
    /// 이름만 믿고 14 로 줄였다가 글자가 작아졌었다(2026-09-02).
    static let bodySmall = g(14)

    /// 앱 이름·로고.
    static func logo(size: CGFloat = 22) -> Font { g(size, bold: true) }
}

extension View {
    /// 호출부를 한 번에 바꿀 수 있게 남겨 둔다.
    func pixelFont(_ font: Font) -> some View { self.font(font) }
}
