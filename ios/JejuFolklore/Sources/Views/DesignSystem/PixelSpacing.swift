import CoreGraphics

/// DESIGN.md §4·§5. 모든 간격은 4의 배수다. 격자에서 벗어나면 픽셀 선이 흐려진다.
enum PixelSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    /// 카드 안쪽 여백
    static let cardPadding: CGFloat = 16
    /// 카드 사이
    static let cardGap: CGFloat = 12
    /// 섹션 사이
    static let sectionGap: CGFloat = 32
    /// 화면 좌우 여백
    static let screenMargin: CGFloat = 16

    static let buttonHeight: CGFloat = 48
    static let tabBarHeight: CGFloat = 56

    // ── 테두리·그림자 ─────────────────────────────────────────
    // 2026-08-20: 2px/3px에서 **4px 통일**로 바꿨다.
    // ① 4의 배수 격자에 맞는다(§4). 2·3px는 이 격자를 벗어난 유일한 값이었다.
    // ② 훨씬 묵직해서 RPG 상자 느낌이 산다. 3px는 웹 카드처럼 보였다.
    // 값을 되돌리면 코너 악센트(8px) 위치가 어긋나므로 함께 고쳐야 한다.

    /// 배지처럼 작은 것의 테두리
    static let borderThin: CGFloat = 4
    /// 카드·버튼·시트·모달 테두리
    static let borderThick: CGFloat = 4
    /// 어긋난 단색 그림자 오프셋 (blur 0)
    static let shadowOffset: CGFloat = 4
    /// 카드 네 귀퉁이의 잉크 사각형 한 변 (테두리의 2배)
    static let cornerAccent: CGFloat = 8
}
