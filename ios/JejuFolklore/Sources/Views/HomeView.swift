import SwiftUI

/// 홈 — 제주 대표 장소 10곳이 주인공이다 (`docs/공고.md` §2).
///
/// 목록을 홈에 둔다. 별도 「탐험」 탭에 두면 홈과 같은 내용이 두 곳에 생긴다.
/// 순서는 **비짓제주 실제 여행 일정 9,134개의 등장 빈도**이고, 오디 해설이 있는 곳만 온다.
/// ⚠️ 9,134는 **일정 수**다. 사람 수가 아니다 — 한 사람이 여러 일정을 만들 수 있다
/// (서버 `services/home_places.py`).
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    @State private var presentedCourse: Course?
    @State private var selectedPlace: HomePlace?

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "놀멍봅서", isAppName: true)

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    placesSection
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
        // 장소 상세로는 **밀어 넣는다**(시트가 아니다). 사진·해설·이용정보가 길고,
        // 뒤로가기·스와이프가 시스템 내비게이션에 붙어 있어야 한다(DESIGN.md §6 시스템 크롬).
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place.asCoursePlace)
        }
        .task { await vm.loadHome() }
        .sheet(item: $presentedCourse) { course in
            NavigationStack { CoursePreviewView(course: course, hasNext: false) }
        }
    }

    // MARK: - 제주에서 가볼 곳 (홈의 주인공)

    @ViewBuilder
    private var placesSection: some View {
        if !vm.places.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                PixelSectionHeader(title: "제주에서 가볼 곳", icon: .mapPin)

                Text("실제 여행 일정 약 9천 개에서 많이 나온 순서예요.")
                    .font(PixelFont.body)
                    .foregroundStyle(PixelColor.inkWeak)

                ForEach(Array(vm.places.enumerated()), id: \.element.id) { index, place in
                    HomePlaceCard(place: place, isTopPick: index == 0) {
                        selectedPlace = place
                    }
                }
            }
        }
    }

    // MARK: - 오늘의 추천 코스 (코스 탭으로 가는 곁길)

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
