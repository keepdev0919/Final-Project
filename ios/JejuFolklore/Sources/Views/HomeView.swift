import SwiftUI
import CoreLocation

/// 홈. 설계 §1 — **성산 카드가 최상단·가장 크게** 온다.
///
/// 유료 콘텐츠 진입을 코스 추천에 종속시키지 않는 이유: 무료 코스는 9,000개에서
/// 뽑히지만 유료 여정은 v1에서 1개뿐이라, 추천 결과에 성산이 없으면 사용자도
/// 심사위원도 핵심 기능을 못 만난다.
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var location = LocationService.shared

    @State private var presentedCourse: Course?
    @State private var presentedJourney: Journey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                journeySection
                recommendedCoursesSection

                if vm.isLoading {
                    Text("불러오는 중…")
                        .pixelFont(PixelFont.bodySmall)
                        .foregroundStyle(PixelColor.inkWeak)
                        .frame(maxWidth: .infinity)
                }

                if let message = vm.errorMessage {
                    Text(message)
                        .pixelFont(PixelFont.badge)
                        .foregroundStyle(PixelColor.locked)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.vertical, PixelSpacing.xl)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationTitle("놀멍봅서")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            LocationService.shared.requestWhenInUseAuthorization()
            await vm.loadHome()
        }
        .sheet(item: $presentedCourse) { course in
            NavigationStack {
                CoursePreviewView(course: course, hasNext: false)
            }
        }
        // 여정 소개 화면은 묶음 B에서 붙인다. 지금은 자리만 잡아 둔다.
        .sheet(item: $presentedJourney) { journey in
            JourneyPlaceholderSheet(journey: journey)
        }
    }

    // MARK: - 여정 (최상단)

    @ViewBuilder
    private var journeySection: some View {
        if !vm.journeys.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                Text("현장에서 듣는 이야기")
                    .pixelFont(PixelFont.screenTitle)
                    .foregroundStyle(PixelColor.ink)

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

    // MARK: - 추천 코스 (무료 훅)

    @ViewBuilder
    private var recommendedCoursesSection: some View {
        if !vm.recommendedCourses.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                Text("오늘의 추천 코스")
                    .pixelFont(PixelFont.screenTitle)
                    .foregroundStyle(PixelColor.ink)

                ForEach(vm.recommendedCourses) { course in
                    Button {
                        presentedCourse = course
                    } label: {
                        PixelCard {
                            VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                                Text(course.title)
                                    .pixelFont(PixelFont.cardTitle)
                                    .foregroundStyle(PixelColor.ink)
                                    .multilineTextAlignment(.leading)
                                Text("\(course.durationDays)일 · 장소 \(course.places.count)곳")
                                    .pixelFont(PixelFont.badge)
                                    .foregroundStyle(PixelColor.inkWeak)
                            }
                            .padding(PixelSpacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
