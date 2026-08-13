import SwiftUI

/// 내 것 탭. 설계 §1 — **이 탭은 필수다.**
/// 애플은 유료 콘텐츠 앱에 구매 복원 경로를, 로그인 있는 앱에 계정 삭제
/// 경로를 요구한다. 없으면 심사에서 거절된다.
///
/// 구매한 이야기 목록과 구매 복원은 **묶음 C(결제)** 에서 붙인다.
/// 동작하지 않는 복원 버튼을 미리 두면 오히려 심사에서 문제가 된다.
struct MineView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                ProfileSection()
                    .environmentObject(authManager)

                // 공지가 지정한 유일한 형식. 텍스트만 허용되고 공사 CI/BI 로고는 금지다.
                Text("출처: ⓒ한국관광공사")
                    .pixelFont(PixelFont.badge)
                    .foregroundStyle(PixelColor.inkWeak)
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.vertical, PixelSpacing.xl)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("내 것")
        .navigationBarTitleDisplayMode(.inline)
    }
}
