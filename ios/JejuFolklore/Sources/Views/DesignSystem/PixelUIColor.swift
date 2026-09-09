import SwiftUI
import UIKit

/// UIKit 쪽에서 쓰는 팔레트 다리.
///
/// 지도 라벨 일부는 `MKAnnotationView` 안에서 `UILabel`·`UIView`로 그린다.
/// 거기서는 SwiftUI `Color`를 쓸 수 없다.
///
/// ⚠️ **색값(0x…)을 여기에 다시 적지 않는다.** `PixelColor`에서 변환만 한다.
/// 값을 두 곳에 두면 한쪽만 바뀌어 라이트/다크가 어긋난다(2026-08-20 팔레트 교체 때
/// 겪은 것과 같은 종류의 사고). `UIColor(Color)`는 다크 모드 전환도 그대로 따라간다.
enum PixelUIColor {
    static let ink       = UIColor(PixelColor.ink)
    static let inkWeak   = UIColor(PixelColor.inkWeak)
    static let surface   = UIColor(PixelColor.surface)
    static let primary   = UIColor(PixelColor.primary)
    static let onPrimary = UIColor(PixelColor.onPrimary)
    static let surfaceMid = UIColor(PixelColor.surfaceMid)
    static let background = UIColor(PixelColor.background)
    // ⚠️ 권역 색은 더 이상 여기서 오지 않는다 — `JejuRegionDef.color`(SwiftUI 쪽)가
    // 정본이다 (2026-09-09). 아래 둘은 UIKit 쪽에서 쓸 일이 생길 때를 위해 남긴다.
    static let secondary = UIColor(PixelColor.secondary)
    static let tertiary  = UIColor(PixelColor.tertiary)
    static let locked    = UIColor(PixelColor.locked)
    /// 지도에서 선택된 핀. 의미 별칭이라 팔레트가 바뀌어도 따라온다.
    static let accent    = UIColor(PixelColor.accent)
}
