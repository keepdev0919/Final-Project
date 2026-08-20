import SwiftUI
import CoreLocation

/// 홈. 설계 v2 §3 — 오디 제공 장소를 인기도순으로 보여주는 게 중심이다.
///
/// 유료 콘텐츠 진입을 코스 추천에 종속시키지 않는다: 무료 코스는 9,000개에서 뽑히지만
/// 유료 여정은 몇 개뿐이라, 추천 결과에 없으면 사용자도 심사위원도 핵심을 못 만난다.
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var location = LocationService.shared

    @State private var presentedCourse: Course?
    @State private var presentedJourney: Journey?

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "놀멍봅서", isAppName: true)

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    journeySection
                    recommendedCoursesSection
                    statusSection
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
            // "지금 여기예요" 배지 판정용. 지속 추적이 아니라 1회성이다.
            LocationService.shared.requestCurrentLocationOnce()
            await vm.loadHome()
        }
        .sheet(item: $presentedCourse) { course in
            NavigationStack { CoursePreviewView(course: course, hasNext: false) }
        }
        .sheet(item: $presentedJourney) { journey in
            JourneyPlaceholderSheet(journey: journey)
        }
    }

    // MARK: - 현장에서 듣는 이야기

    @ViewBuilder
    private var journeySection: some View {
        if !vm.journeys.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                PixelSectionHeader(title: "현장에서 듣는 이야기", icon: .play)
                ForEach(vm.journeys) { journey in
                    JourneyCard(
                        journey: journey,
                        isNearby: journey.isNearby(location.currentLocation),
                        action: { presentedJourney = journey }
                    )
                }
            }
        }
    }

    // MARK: - 오늘의 추천 코스 (무료 훅)

    @ViewBuilder
    private var recommendedCoursesSection: some View {
        if !vm.recommendedCourses.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                // 시안은 정보 계열 섹션 헤더에 파랑을 쓴다.
                PixelSectionHeader(title: "오늘의 추천 코스", icon: .map,
                                   accent: PixelColor.secondary)
                ForEach(vm.recommendedCourses) { course in
                    Button { presentedCourse = course } label: {
                        courseRow(course)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        PixelCard(corners: false) {
            VStack(alignment: .leading, spacing: PixelSpacing.s) {
                Text(course.title)
                    .font(PixelFont.sectionTitle)
                    .foregroundStyle(PixelColor.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: PixelSpacing.s) {
                    PixelChip(text: "\(course.durationDays)일",
                              fill: PixelColor.secondaryContainer,
                              label: PixelColor.onSecondaryContainer)
                    PixelChip(text: "장소 \(course.places.count)곳")
                }
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 상태

    @ViewBuilder
    private var statusSection: some View {
        if vm.isLoading {
            Text("불러오는 중…")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
                .frame(maxWidth: .infinity)
        } else if let message = vm.errorMessage {
            PixelCard(corners: false) {
                VStack(alignment: .leading, spacing: PixelSpacing.m) {
                    Text(message)
                        .font(PixelFont.body)
                        .foregroundStyle(PixelColor.ink)
                    PixelButton(title: "다시 시도", style: .plain) {
                        Task { await vm.reload() }
                    }
                }
                .padding(PixelSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
