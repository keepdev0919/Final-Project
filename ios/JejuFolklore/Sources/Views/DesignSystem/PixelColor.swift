import SwiftUI
import UIKit

/// DESIGN.md §2 팔레트. **여기 없는 색을 화면에서 만들지 않는다.**
///
/// 값을 바꾸려면 DESIGN.md를 먼저 고치고 `tests/test_design_tokens.py`를 통과시킨다.
/// 대비 기준은 그 테스트의 docstring에 있다.
enum PixelColor {
    static let background = adaptive(light: 0xF4EFE4, dark: 0x14181A)
    static let surface    = adaptive(light: 0xFFFFFF, dark: 0x1E2427)
    static let ink        = adaptive(light: 0x1E1B18, dark: 0xEDE7DC)
    static let inkWeak    = adaptive(light: 0x6B635A, dark: 0x9A9187)
    static let primary    = adaptive(light: 0x1E6F6B, dark: 0x4FB3AD)
    static let accent     = adaptive(light: 0xF2B233, dark: 0xFFC759)
    static let locked     = adaptive(light: 0xC9503C, dark: 0xE0705A)
    static let done       = adaptive(light: 0x4E8C3F, dark: 0x6FAE5E)

    /// 밝은 배지 배경(강조·잠김·완료) 위에 올리는 글자색. **모드와 무관하게 고정한다.**
    /// 다크 모드 잉크(#EDE7DC)를 강조색 위에 올리면 1.26:1이 되어 글자가 사라진다.
    static let inkFixedDark = fixed(0x1E1B18)

    // MARK: - 내부

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    private static func fixed(_ rgb: UInt32) -> Color {
        Color(UIColor(rgb: rgb))
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue:  CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
