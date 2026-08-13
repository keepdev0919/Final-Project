import SwiftUI

/// 스토리 탭 — 이야기가 준비된 장소 목록. v1은 성산 1개다 (설계 §1).
struct StoryListView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var location = LocationService.shared
    @State private var presentedJourney: Journey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                if vm.journeys.isEmpty && !vm.isLoading {
                    Text("아직 준비된 이야기가 없어요")
                        .pixelFont(PixelFont.body)
                        .foregroundStyle(PixelColor.inkWeak)
                        .frame(maxWidth: .infinity)
                        .padding(.top, PixelSpacing.xxl)
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
            .padding(.vertical, PixelSpacing.xl)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("스토리")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            LocationService.shared.requestCurrentLocationOnce()
            await vm.loadHome()
        }
        .sheet(item: $presentedJourney) { journey in
            JourneyPlaceholderSheet(journey: journey)
        }
    }
}
