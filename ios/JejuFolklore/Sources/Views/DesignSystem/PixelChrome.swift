import SwiftUI
import UIKit

/// 시스템 크롬(내비게이션 바·리스트·시트)을 팔레트에 맞춘다. 앱 시작 시 한 번 부른다.
///
/// **왜 화면마다 직접 안 그리는가.** 탭 뿌리 화면은 `PixelTopBar`를 쓰지만,
/// 밀려 올라오는 화면(장소 상세·코스 미리보기·탐험 중)은 뒤로가기·툴바 버튼·
/// 스와이프 back 제스처가 시스템 내비게이션 바에 묶여 있다. 그걸 직접 다시 짜면
/// 다섯 화면의 이동 동작을 전부 새로 검증해야 한다. 외형만 여기서 갈아입히면
/// 동작은 그대로 두고 색·글자만 통일된다.
enum PixelChrome {
    static func apply() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = PixelUIColor.surfaceMid
        // 하단 4px 잉크 선 — 시안의 두꺼운 경계. shadowImage는 높이를 지킨다.
        bar.shadowColor = nil
        bar.shadowImage = solid(PixelUIColor.ink, height: 4)

        let title: [NSAttributedString.Key: Any] = [
            .foregroundColor: PixelUIColor.ink,
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
        ]
        bar.titleTextAttributes = title
        bar.largeTitleTextAttributes = [
            .foregroundColor: PixelUIColor.ink,
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
        ]

        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().tintColor = PixelUIColor.ink

        // List·Form의 회색 바탕을 팔레트 배경으로.
        UITableView.appearance().backgroundColor = PixelUIColor.background
    }

    /// 1×height 단색 이미지. `shadowImage`는 가로로 늘어나므로 폭 1이면 된다.
    private static func solid(_ color: UIColor, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: height)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: height))
        }
    }
}
