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
    // 제주 4개 권역을 구분하는 데 쓴다 — 팔레트 밖 색(보라·분홍)을 쓰지 않으려고
    static let secondary = UIColor(PixelColor.secondary)
    static let tertiary  = UIColor(PixelColor.tertiary)
    static let locked    = UIColor(PixelColor.locked)
}
