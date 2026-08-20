import SwiftUI
import UIKit

/// DESIGN.md §2 팔레트. **여기 없는 색을 화면에서 만들지 않는다.**
///
/// 2026-08-20: **Stitch 시안의 팔레트를 그대로 가져왔다.** 라이트 값은 시안 CSS에서 복사한
/// 것이고, 시안이 라이트 전용이라 다크는 시안이 함께 준 `*-fixed-dim`·`inverse-*` 값을
/// 써서 Material 관례대로 파생시킨 뒤 대비를 실측했다.
///
/// 값을 바꾸려면 DESIGN.md를 먼저 고치고 `tests/test_design_tokens.py`를 통과시킨다.
enum PixelColor {

    // ── 면 (표면 단계) ──────────────────────────────────────────
    static let background     = adaptive(light: 0xFBF8FF, dark: 0x12141F)
    static let surface        = adaptive(light: 0xFFFFFF, dark: 0x22243A)
    static let surfaceLow     = adaptive(light: 0xF4F2FF, dark: 0x1B1D2E)
    static let surfaceMid     = adaptive(light: 0xEDECFF, dark: 0x282B44)
    static let surfaceHigh    = adaptive(light: 0xE6E6FD, dark: 0x30334E)
    static let surfaceVariant = adaptive(light: 0xE1E1F7, dark: 0x3A3D58)
    static let surfaceDim     = adaptive(light: 0xD8D8EF, dark: 0x0D0F18)

    // ── 글자 ────────────────────────────────────────────────────
    static let ink     = adaptive(light: 0x181A2A, dark: 0xF0EFFF)
    static let inkWeak = adaptive(light: 0x3D4A3F, dark: 0x9EA8A0)

    // ── 선 (테두리·구분선). 비텍스트라 대비 기준이 3:1이다 ──────────
    static let outline        = adaptive(light: 0x6D7B6E, dark: 0x8A9A8B)
    static let outlineVariant = adaptive(light: 0xBCCABC, dark: 0x4A5A4B)

    // ── 주색 (초록) ─────────────────────────────────────────────
    static let primary            = adaptive(light: 0x006D39, dark: 0x51E088)
    static let onPrimary          = adaptive(light: 0xFFFFFF, dark: 0x00210D)
    static let primaryContainer   = adaptive(light: 0x38CC77, dark: 0x005229)
    static let onPrimaryContainer = adaptive(light: 0x005129, dark: 0x70FDA2)

    // ── 보조색 (파랑) ───────────────────────────────────────────
    static let secondary            = adaptive(light: 0x0062A2, dark: 0x9DCAFF)
    static let onSecondary          = adaptive(light: 0xFFFFFF, dark: 0x001D35)
    static let secondaryContainer   = adaptive(light: 0x54ABFD, dark: 0x00497C)
    static let onSecondaryContainer = adaptive(light: 0x003E69, dark: 0xD1E4FF)

    // ── 삼차색 (금색) ───────────────────────────────────────────
    static let tertiary            = adaptive(light: 0x735C00, dark: 0xEEC215)
    static let onTertiary          = adaptive(light: 0xFFFFFF, dark: 0x231B00)
    static let tertiaryContainer   = adaptive(light: 0xD9AF00, dark: 0x574500)
    static let onTertiaryContainer = adaptive(light: 0x554400, dark: 0xFFE085)
    /// 시안의 `tertiary-fixed` — 모드와 무관하게 같다. 칩·배지에 쓴다.
    static let tertiaryFixed   = adaptive(light: 0xFFE085, dark: 0xFFE085)
    static let onTertiaryFixed = adaptive(light: 0x231B00, dark: 0x231B00)

    // ── 오류 ────────────────────────────────────────────────────
    static let error   = adaptive(light: 0xBA1A1A, dark: 0xFFB4AB)
    static let onError = adaptive(light: 0xFFFFFF, dark: 0x93000A)

    // ── 의미 별칭 ────────────────────────────────────────────────
    //
    // 화면 코드는 "무슨 색"이 아니라 "무슨 뜻"으로 쓴다. 색을 바꿀 때
    // 화면을 안 건드리려면 이 층이 필요하다.

    /// 가라앉은 면 — 섹션 안쪽·비활성
    static let sunk = surfaceMid
    /// 강조 — 스티커 배지·CTA (금색)
    static let accent   = tertiaryContainer
    static let onAccent = onTertiaryContainer
    /// 완료 — 들은 것·수집 완료 (밝은 초록)
    static let done   = primaryContainer
    static let onDone = onPrimaryContainer
    /// 잠김 — 잠금·경고
    static let locked   = error
    static let onLocked = onError

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
