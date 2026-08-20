import SwiftUI

struct CourseListView: View {
    @ObservedObject var vm: CourseRecommendViewModel
    @State private var navigateToPreview = false
    @State private var shouldLoadNext = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PixelColor.background.ignoresSafeArea()

            if vm.isLoadingList {
                loadingView
            } else if let err = vm.errorMessage, !vm.isLoadingDetail {
                errorView(err)
            } else if vm.courseList.isEmpty {
                emptyView
            } else {
                courseListContent
            }

            if vm.isLoadingDetail {
                LoadingOverlay(step: vm.loadingStep)
            }
        }
        .navigationTitle("추천 코스")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToPreview) {
            if let course = vm.selectedCourse {
                CoursePreviewView(
                    course: course,
                    hasNext: vm.hasNextCourse,
                    onNext: { shouldLoadNext = true },
                    onReset: { vm.reset() }
                )
            }
        }
        .onChange(of: navigateToPreview) {
            // 사용자가 PreviewView에서 뒤로 가면 selectedCourse 비워서 리스트 화면 복귀
            if !navigateToPreview {
                if shouldLoadNext {
                    shouldLoadNext = false
                    Task { await vm.advanceToNextCourse() }
                } else {
                    vm.selectedCourse = nil
                }
            }
        }
        .onChange(of: vm.selectedCourse) {
            if vm.selectedCourse != nil {
                navigateToPreview = true
            }
        }
        .alert("코스를 가져오지 못했어요", isPresented: Binding(
            get: { vm.errorMessage != nil && !vm.isLoadingList },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "다시 시도해주세요.")
        }
        // 탐험 완료 시 자신도 pop → TasteDiscoveryView(NavigationStack root)까지 연쇄적으로 복귀.
        .onReceive(NotificationCenter.default.publisher(for: .exploreDidComplete)) { _ in
            navigateToPreview = false
            dismiss()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("AI가 코스를 추천하고 있어요...")
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
        }
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: 12) {
            PixelIcon(.warn, size: 48, color: PixelColor.locked)
            Text(err)
                .font(PixelFont.body)
                .multilineTextAlignment(.center)
                .foregroundColor(PixelColor.inkWeak)
            Button("다시 시도") {
                Task { await vm.fetchList() }
            }
            .buttonStyle(PixelButtonStyle(.primary))
        }
        .padding(32)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text("추천 코스가 없어요.")
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
            Button("처음으로") { vm.reset() }
                .buttonStyle(PixelButtonStyle(.primary))
        }
        .padding(32)
    }

    // MARK: - Top 3 List

    private var courseListContent: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(alignment: .leading, spacing: 4) {
                Text("당신을 위한 \(vm.courseList.count)가지 코스")
                    .font(PixelFont.sectionTitle)
                Text("마음에 드는 코스를 골라 탐험을 시작해보세요")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.inkWeak)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(vm.courseList.enumerated()), id: \.element.id) { index, course in
                        CourseCard(
                            course: course,
                            rank: index + 1,
                            onTap: {
                                Task { await vm.selectCourse(at: index) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // 처음으로 버튼 (하단)
            Button {
                vm.reset()
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(.refresh, size: 16)
                    Text("취향 다시 고르기")
                }
                .font(PixelFont.body)
                .foregroundColor(PixelColor.inkWeak)
                .padding(.vertical, 8)
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - CourseCard

private struct CourseCard: View {
    let course: CourseListItem
    let rank: Int
    let onTap: () -> Void

    // 코스에서 보여줄 대표 장소 최대 3개 (day 1 우선)
    private var previewPlaceNames: [String] {
        let day1 = course.places.filter { $0.day == 1 }
        let pool = day1.isEmpty ? course.places : day1
        return Array(pool.prefix(3)).map { $0.name }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return PixelColor.primary
        case 2: return PixelColor.primary.opacity(0.75)
        default: return PixelColor.primary.opacity(0.55)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // 헤더: 순위 + 제목
                HStack(alignment: .top, spacing: 10) {
                    Text("\(rank)")
                        .font(PixelFont.body)
                        .foregroundColor(rank == 1 ? PixelColor.onPrimary : PixelColor.ink)
                        .frame(width: 28, height: 28)
                        .background(rankColor)
                        .clipShape(Rectangle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.title.isEmpty ? "이름 없는 코스" : course.title)
                            .font(PixelFont.label)
                            .foregroundColor(PixelColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            PixelIcon(.calendar, size: 14)
                            Text("\(course.durationDays)일 일정")
                            Text("·")
                            PixelIcon(.mapPin, size: 14)
                            Text("\(course.places.count)곳")
                        }
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                    }

                    Spacer()

                    PixelIcon(.forward, size: 16)
                        .foregroundColor(PixelColor.inkWeak)
                }

                // 대표 장소 칩
                if !previewPlaceNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(previewPlaceNames, id: \.self) { name in
                            Text(name)
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(PixelColor.surfaceLow)
                                .clipShape(Rectangle())
                                .lineLimit(1)
                        }
                        if course.places.count > previewPlaceNames.count {
                            Text("+\(course.places.count - previewPlaceNames.count)")
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.inkWeak)
                                .padding(.horizontal, 8)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(
                Rectangle()
                    .fill(PixelColor.surface)
                    
            )
            .overlay(
                Rectangle()
                    .stroke(PixelColor.inkWeak.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
