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
        // 하단 경계선.
        //
        // ⚠️ `shadowImage`에 4px 잉크 이미지를 굽는 방법을 썼다가 되돌렸다. 두 가지가 깨진다:
        // ① `shadowColor = nil`은 "그림자 숨김"이라 선이 아예 안 나올 수 있다.
        // ② `UIGraphicsImageRenderer`는 `App.init()` 시점의 모드(윈도가 없어 라이트)로
        //    색을 **비트맵에 굽는다** → 다크 모드에서 바 배경만 어두워지고 선은 라이트
        //    잉크로 남아 경계가 사라진다. 실행 중 모드를 바꿔도 갱신되지 않는다.
        // 두께(4px)를 포기하고 동적 색을 택했다. 4px 두꺼운 경계는 탭 뿌리 화면의
        // `PixelTopBar`가 갖는다 — 밀려 올라온 화면은 다른 상태다 (DESIGN.md §6).
        bar.shadowColor = PixelUIColor.ink

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

        // ⚠️ `UITableView.appearance()`로 List 바탕을 칠하려 했다가 지웠다.
        // iOS 16+ SwiftUI `List`는 UICollectionView 기반이라 효과가 없다.
        // 화면마다 `.scrollContentBackground(.hidden)` + `.background(...)`를 쓴다.
    }
}
