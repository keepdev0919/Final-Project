import SwiftUI
import UIKit

/// **이 파일이 팔레트 정본이다. 여기 없는 색을 화면에서 만들지 않는다.**
///
/// 2026-08-20: **Stitch 시안의 팔레트를 그대로 가져왔다.** 라이트 값은 시안 CSS에서 복사한
/// 것이고, 시안이 라이트 전용이라 다크는 시안이 함께 준 `*-fixed-dim`·`inverse-*` 값을
/// 써서 Material 관례대로 파생시킨 뒤 대비를 실측했다.
///
/// 값을 바꾸려면 이 파일을 고치고 `tests/test_design_tokens.py`를 통과시킨다.
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
    /// ⚠️ 라이트 값만 시안(#D9AF00)에서 벗어나 있다. 시안 값은 겨자·황동에 가까워
    /// 「금색」으로 읽히지 않았고, 이 색이 코스 탭에서 **고르는 자리 전부**(권역 버튼·
    /// 기간 칩)를 맡게 되면서 눈에 걸렸다 (2026-09-09 조익준님 결정).
    /// 짝 글자색(#554400)과의 대비는 4.94 → 6.03:1 로 오히려 좋아진다.
    static let tertiaryContainer   = adaptive(light: 0xFFC61A, dark: 0x574500)
    static let onTertiaryContainer = adaptive(light: 0x554400, dark: 0xFFE085)
    /// 시안의 `tertiary-fixed` — 모드와 무관하게 같다. 칩·배지에 쓴다.
    static let tertiaryFixed   = adaptive(light: 0xFFE085, dark: 0xFFE085)
    static let onTertiaryFixed = adaptive(light: 0x231B00, dark: 0x231B00)

    // ── 오류 ────────────────────────────────────────────────────
    static let error   = adaptive(light: 0xBA1A1A, dark: 0xFFB4AB)
    static let onError = adaptive(light: 0xFFFFFF, dark: 0x93000A)

    // ── 권역 (제주 4개 권역 + 전체) ────────────────────────────────
    //
    // 권역은 **앱 전체에서 같은 색**이다 (2026-09-09 조익준님 결정) — 코스 카드
    // 배지, 코스 탭 픽셀 제주 지도의 권역 버튼, 지도 탭 권역 칩이 같은 색을 쓴다.
    // 「서부는 보라」가 화면마다 다른 뜻이 되면 색이 이름표 노릇을 못 한다.
    //
    // 색 배정은 **해가 뜨고 지는 쪽**이다. 외우기 쉽고 제주 지리와도 맞는다.
    //
    //     동부 (성산·구좌)  주황   해돋이
    //     서부 (한림·애월)  보라   노을
    //     북부 (제주시)     파랑   도시·바다 — 팔레트에 이미 있는 파랑을 쓴다
    //     남부 (서귀포)     청록   남쪽 바다
    //     전체              잉크   권역이 아니라 「여러 권역에 걸침」이라 색조를 안 준다
    //
    // 초록과 빨강은 권역에 쓰지 않는다. 초록은 「플레이 시작」 실행색이고 빨강은
    // 「잠김·오류」다. 권역에 얹으면 남부 코스 카드가 경고처럼 읽힌다.
    //
    // ⚠️ 2026-08-20 에 권역 색에서 보라·분홍을 뺀 적이 있다. 그때 문제는 색조가
    // 아니라 **팔레트 밖 시스템 색**(`.purple`)을 화면에서 직접 쓴 것이었다
    // (`tests/test_design_no_system_colors.py`). 그 테스트가 요구한 대로 팔레트
    // 안으로 들여오고 짝 글자색과 대비를 못 박아 다시 쓴다.
    static let regionEast    = adaptive(light: 0xFF9E3D, dark: 0x6E3A00)
    static let onRegionEast  = adaptive(light: 0x4A2200, dark: 0xFFDCC2)
    static let regionWest    = adaptive(light: 0xA98BFF, dark: 0x4A2E8C)
    static let onRegionWest  = adaptive(light: 0x2E1065, dark: 0xDCC9FF)
    static let regionSouth   = adaptive(light: 0x3ECFD5, dark: 0x004F53)
    static let onRegionSouth = adaptive(light: 0x00363A, dark: 0xA8F0F5)

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

    /// 권역 북부 — 파랑은 팔레트에 이미 있어 새로 만들지 않는다
    static let regionNorth   = secondaryContainer
    static let onRegionNorth = onSecondaryContainer
    /// 권역 전체 — 색조 없이 잉크. 「여기가 어느 권역이다」가 아니라 「권역을 안 가린다」
    static let regionAll   = ink
    static let onRegionAll = background

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
