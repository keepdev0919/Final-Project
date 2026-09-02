import CoreGraphics

/// 간격은 4의 배수다. 이 파일이 정본이다.
enum PixelSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    /// 카드 안쪽 여백
    static let cardPadding: CGFloat = 16
    /// 카드 사이
    static let cardGap: CGFloat = 16
    /// 섹션 사이
    static let sectionGap: CGFloat = 32
    /// 화면 좌우 여백
    static let screenMargin: CGFloat = 20

    static let buttonHeight: CGFloat = 48
    static let tabBarHeight: CGFloat = 80

    // ── 테두리·그림자 ────────────────────────────
    // **테두리는 얇고 그림자는 크다.** 이게 이 디자인의 정체다.
    // 2026-08-20: 둘 다 4px로 뒀다가 뭉툭해져서 시안 값으로 되돌렸다.

    /// 모든 테두리는 2px다. 큰 상자의 겉테두리(§5 이중 테두리)만 4px.
    static let border: CGFloat = 2
    /// 이중 테두리의 겉테두리, 상단바·탭바의 구분선
    static let borderHeavy: CGFloat = 4

    /// 카드·시트 그림자 (대각선)
    static let shadowCard: CGFloat = 4
    /// 칩·배지·작은 아이템 그림자
    static let shadowSmall: CGFloat = 2
    /// 강조 상자(대화상자·히어로) 그림자
    static let shadowStrong: CGFloat = 8
    /// 버튼 그림자 — **아래로만.** 버튼은 눌리는 물건이라 옆으로 밀리면 안 된다.
    static let shadowButton: CGFloat = 4

    /// 카드 귀퉁이 잉크 사각형 한 변
    static let cornerAccent: CGFloat = 8
    /// 코너 악센트를 테두리 밖으로 빼는 거리. 안쪽에 두면 잉크 위 잉크라 안 보인다.
    static let cornerAccentOut: CGFloat = 2
}
