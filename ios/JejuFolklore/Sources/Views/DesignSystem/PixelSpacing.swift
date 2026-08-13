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

    /// 버튼·입력창·배지 테두리
    static let borderThin: CGFloat = 2
    /// 카드·시트·모달 테두리, 선택 상태
    static let borderThick: CGFloat = 3
    /// 어긋난 단색 그림자 오프셋 (blur 0)
    static let shadowOffset: CGFloat = 3
}
