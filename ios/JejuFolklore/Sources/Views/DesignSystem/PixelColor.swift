import SwiftUI
import UIKit

/// DESIGN.md §2 팔레트. **여기 없는 색을 화면에서 만들지 않는다.**
///
/// 2026-08-20: Stitch 시안 색으로 전면 교체했다. 라이트 값은 시안 CSS에서 그대로 가져오고,
/// 시안이 라이트 전용이라 다크는 같은 색조로 파생시킨 뒤 대비를 실측했다.
///
/// 값을 바꾸려면 DESIGN.md를 먼저 고치고 `tests/test_design_tokens.py`를 통과시킨다.
enum PixelColor {
    // ── 면 ──
    static let background = adaptive(light: 0xFBF8FF, dark: 0x12141F)
    static let surface    = adaptive(light: 0xFFFFFF, dark: 0x22243A)
    static let sunk       = adaptive(light: 0xEDECFF, dark: 0x1B1D2E)

    // ── 글자 ──
    static let ink        = adaptive(light: 0x181A2A, dark: 0xF0EFFF)
    static let inkWeak    = adaptive(light: 0x3D4A3F, dark: 0x9EA8A0)

    // ── 채움색 ──
    static let primary    = adaptive(light: 0x006D39, dark: 0x38CC77)
    static let accent     = adaptive(light: 0xD9AF00, dark: 0xEEC215)
    static let done       = adaptive(light: 0x38CC77, dark: 0x70FDA2)
    static let locked     = adaptive(light: 0xBA1A1A, dark: 0xFFB4AB)

    // ── 채움색 위에 올리는 글자 ──
    //
    // ⚠️ **모드마다 다르다.** 라이트의 primary(#006D39)는 어두운 초록이라 흰 글자가 맞고,
    // 다크의 primary(#38CC77)는 밝은 초록이라 어두운 글자가 맞다. 하나로 고정하면
    // 한쪽 모드에서 글자가 사라진다 (2026-08-14에 1.26:1로 겪은 것과 같은 종류).
    // `tests/test_design_tokens.py`가 네 짝을 모두 검사한다.
    static let onPrimary  = adaptive(light: 0xFFFFFF, dark: 0x181A2A)
    static let onAccent   = adaptive(light: 0x181A2A, dark: 0x181A2A)
    static let onDone     = adaptive(light: 0x181A2A, dark: 0x181A2A)
    static let onLocked   = adaptive(light: 0xFFFFFF, dark: 0x181A2A)

    // MARK: - 내부

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue:  CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
