import SwiftUI

/// DESIGN.md §3. 비트맵 폰트는 **설계 크기의 정수배**에서만 선명하다.
/// 그래서 글자 크기를 즉석에서 정하지 않고 아래 사다리만 쓴다.
///
/// ⚠️ 긴 글(이야기 스크립트 전문·약관·오류 상세)에는 픽셀 폰트를 쓰지 않는다.
/// 눈이 빨리 피로해진다. `longform(_:)`을 쓴다.
enum PixelFont {
    /// 폰트 이름과 설계 픽셀 높이. 확대는 이 높이의 **정수배**로만 한다.
    struct Face {
        /// ⚠️ 파일명이 아니라 **PostScript 이름**이다 (Galmuri11.ttf → "Galmuri11-Regular").
        /// 틀리면 예외 없이 시스템 폰트로 폴백되어 화면이 멀쩡해 보인다.
        let name: String
        /// 설계 픽셀 높이 (Galmuri9 → 9)
        let unit: CGFloat
        /// 기본 배율
        let baseMultiple: Int

        var baseSize: CGFloat { unit * CGFloat(baseMultiple) }
    }

    static let screenTitle = Face(name: "Galmuri11-Regular", unit: 11, baseMultiple: 2)  // 22
    static let cardTitle   = Face(name: "Galmuri11-Regular", unit: 11, baseMultiple: 2)  // 22
    static let body        = Face(name: "Galmuri11-Regular", unit: 11, baseMultiple: 2)  // 22
    static let bodySmall   = Face(name: "Galmuri11-Regular", unit: 11, baseMultiple: 1)  // 11
    static let button      = Face(name: "Galmuri11-Regular", unit: 11, baseMultiple: 2)  // 22
    static let badge       = Face(name: "Galmuri9-Regular",  unit: 9,  baseMultiple: 2)  // 18
    static let number      = Face(name: "Galmuri14-Regular", unit: 14, baseMultiple: 2)  // 28

    /// 긴 글 전용. 시스템 폰트(Apple SD Gothic Neo)를 쓴다. Dynamic Type을 그대로 따른다.
    static func longform(_ size: CGFloat = 17) -> Font {
        .system(size: size)
    }
}

/// 픽셀 폰트를 **정수배 단계로만** 확대한다 (DESIGN.md §3).
///
/// `.custom(_:size:relativeTo:)`를 쓰면 iOS가 1.3배 같은 어중간한 배율로 늘려
/// 도트가 흐려진다. 접근성 설정을 무시할 수도 없으므로, 배율을 정수로 올려
/// 22 → 33 → 44 처럼 단계를 뛴다.
struct PixelFontModifier: ViewModifier {
    let face: PixelFont.Face
    @Environment(\.dynamicTypeSize) private var typeSize

    private var multiple: Int {
        let extra: Int
        switch typeSize {
        case .xSmall, .small, .medium, .large: extra = 0
        case .xLarge, .xxLarge:                extra = 1
        default:                               extra = 2   // xxxLarge 이상 · 접근성 크기
        }
        return face.baseMultiple + extra
    }

    func body(content: Content) -> some View {
        content.font(.custom(face.name, fixedSize: face.unit * CGFloat(multiple)))
    }
}

extension View {
    /// 픽셀 폰트를 적용한다. `.font(...)` 대신 이걸 쓴다.
    func pixelFont(_ face: PixelFont.Face) -> some View {
        modifier(PixelFontModifier(face: face))
    }
}
