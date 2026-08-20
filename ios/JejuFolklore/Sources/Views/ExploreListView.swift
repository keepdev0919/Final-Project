import SwiftUI

/// 스토리 탭 — 이야기가 준비된 장소 목록.
struct StoryListView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var location = LocationService.shared
    @State private var presentedJourney: Journey?

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "스토리")

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                    PixelSectionHeader(title: "준비된 이야기", icon: .play)

                    if vm.journeys.isEmpty && !vm.isLoading {
                        emptyState
                    }
                    ForEach(vm.journeys) { journey in
                        JourneyCard(
                            journey: journey,
                            isNearby: journey.isNearby(location.currentLocation),
                            action: { presentedJourney = journey }
                        )
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
        .task {
            LocationService.shared.requestCurrentLocationOnce()
            await vm.loadHome()
        }
        .sheet(item: $presentedJourney) { journey in
            JourneyPlaceholderSheet(journey: journey)
        }
    }

    private var emptyState: some View {
        PixelCard(corners: false) {
            Text("아직 준비된 이야기가 없어요")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
                .frame(maxWidth: .infinity)
                .padding(PixelSpacing.xxl)
        }
    }
}
