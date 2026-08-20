import SwiftUI

/// DESIGN.md §3. **UI 본문은 시스템 산세리프**(Apple SD Gothic Neo)를 쓴다.
///
/// 2026-08-20: 갈무리 픽셀 폰트를 화면 전체에서 뺐다. 시안 4개가 전부 산세리프이고,
/// 시안이 촘촘하고 읽기 쉬운 이유의 절반이 폰트였다. 픽셀 폰트는 같은 크기에서
/// 담기는 정보량이 훨씬 적다.
///
/// 갈무리는 **로고에만** 남긴다 — 짧고, 픽셀 정체성이 필요한 유일한 자리다.
enum PixelFont {
    /// 화면 최상단 큰 제목
    static let screenTitle = Font.system(size: 28, weight: .bold)
    /// 섹션 제목 · 카드 제목
    static let sectionTitle = Font.system(size: 24, weight: .semibold)
    /// 소개문 (본문 크게)
    static let bodyLarge = Font.system(size: 18, weight: .regular)
    /// 본문
    static let body = Font.system(size: 16, weight: .regular)
    /// 라벨 · 버튼 · 칩 — 굵기로 위계를 만든다
    static let label = Font.system(size: 14, weight: .bold)
    /// 작은 라벨 · 배지
    static let labelSmall = Font.system(size: 12, weight: .medium)

    /// 앱 이름·로고 전용 픽셀 폰트. 여기 말고는 쓰지 않는다.
    static func logo(size: CGFloat = 22) -> Font {
        .custom("Galmuri11-Regular", fixedSize: size)
    }
}

extension View {
    /// 시스템 폰트라 그냥 `.font()`를 쓰면 되지만, 호출부를 한 번에 바꿀 수 있게 남겨 둔다.
    func pixelFont(_ font: Font) -> some View {
        self.font(font)
    }
}
