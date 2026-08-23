import SwiftUI

/// 홈 — **스테이지 선택 화면**이다 (`docs/공고.md` §2).
///
/// 장소 목록이 아니다. 게임의 스테이지 선택 화면처럼 「여기서 할 일」과 「내 상태」를
/// 보여주고, 해설 길이·운영시간·방문 시간대 같은 여행 정보는 장소 상세로 내렸다.
///
/// 6곳은 **라벨(종류)마다 1등 하나씩** 손으로 골랐다 — 순위 상위 6을 그냥 자르면
/// 바다가 3개가 되어 라벨이 단조로워진다. 무엇을 띄우는지는 서버 `data/home_stage.json`.
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    @State private var presentedCourse: Course?
    @State private var selectedStage: HomeStage?

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "놀멍봅서", isAppName: true)

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    stagesSection
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
        .navigationDestination(item: $selectedStage) { stage in
            PlaceDetailView(place: stage.asCoursePlace)
        }
        .task { await vm.loadHome() }
        .sheet(item: $presentedCourse) { course in
            NavigationStack { CoursePreviewView(course: course, hasNext: false) }
        }
    }

    // MARK: - 밟을 곳 (홈의 주인공)

    @ViewBuilder
    private var stagesSection: some View {
        if !vm.stages.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                PixelSectionHeader(title: "밟을 곳", icon: .target)

                ForEach(vm.stages) { stage in
                    StageCard(stage: stage) { selectedStage = stage }
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
