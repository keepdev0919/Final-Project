import SwiftUI

/// 내 것 탭. 설계 §3 — **이 탭은 필수다.**
/// 애플은 유료 콘텐츠 앱에 구매 복원 경로를, 로그인 있는 앱에 계정 삭제 경로를 요구한다.
/// 없으면 심사에서 거절된다.
///
/// 구매한 이야기 목록과 구매 복원은 결제를 붙일 때 여기에 들어온다.
struct MineView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "내 것")

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                        PixelSectionHeader(title: "내 계정", icon: .person)
                        ProfileSection().environmentObject(authManager)
                    }

                    VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                        PixelSectionHeader(title: "정보", icon: .photo,
                                           accent: PixelColor.secondary)
                        // 공지가 지정한 유일한 형식. 텍스트만 허용되고 공사 CI/BI 로고는 금지다.
                        Text("출처: ⓒ한국관광공사")
                            .font(PixelFont.labelSmall)
                            .foregroundStyle(PixelColor.inkWeak)
                    }
                }
                .padding(.horizontal, PixelSpacing.screenMargin)
                .padding(.top, PixelSpacing.xxl)
                // ⚠️ 직접 만든 탭바는 ScrollView가 알지 못한다. 하단 여백을 주지 않으면
                // 마지막 카드가 탭바에 가린다(2026-08-20에 실제로 겪음).
                .padding(.bottom, PixelSpacing.xxxl)
            }
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}
