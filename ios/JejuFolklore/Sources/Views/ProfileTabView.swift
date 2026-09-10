import SwiftUI

/// 개인정보 처리방침 URL.
///
/// 서버가 함께 서빙한다(`backend/routers/legal.py`). 주소를 baseURL에서 끌어오므로
/// 배포처가 바뀌어도 따라간다. 앱스토어 등록 화면에는 이 경로의 절대 주소를 입력할 것.
private let privacyPolicyURL = URL(string: Config.baseURL + "/privacy")!

/// 내 것 탭. 설계 §3 — **이 탭은 필수다.**
///
/// 로그인 기능은 없다(2026-09-09 제거) — 공모전 심사 제출까지는 불필요하다고 판단.
/// 구매한 이야기 목록과 구매 복원은 결제를 붙일 때 여기에 들어온다.
struct ProfileTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "프로필")

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                        PixelSectionHeader(title: "내 코스", icon: .map,
                                           accent: PixelColor.secondary)
                        MyCourseListView()
                    }

                    // 「정보」 섹션을 걷어냈다 (2026-09-10 조익준님 결정).
                    // 거기 있던 「출처: ⓒ한국관광공사」는 **관광정보가 실제로 쓰이는
                    // 장소 상세 화면**으로 옮겼다. 프로필에 남겨 두면 어느 데이터가
                    // 공사 것인지 알 수 없는 채로 한 줄만 떠 있게 된다.
                    //
                    // ⚠️ 개인정보 처리방침 링크는 남긴다. 앱 안에서 닿을 수 있어야
                    // 하는 것이라 섹션과 함께 지울 수 없다. 제목 없이 조용한 한 줄로 둔다.
                    Link(destination: privacyPolicyURL) {
                        Text("개인정보 처리방침")
                            .pixelFont(PixelFont.labelSmall)
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
