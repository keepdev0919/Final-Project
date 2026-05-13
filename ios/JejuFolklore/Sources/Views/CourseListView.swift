import SwiftUI

struct CourseListView: View {
    @ObservedObject var vm: CourseRecommendViewModel
    @State private var navigateToPreview = false
    @State private var shouldLoadNext = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

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
                    onReset: { vm.reset() },
                    categoryScores: vm.categoryScores
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
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("AI가 코스를 추천하고 있어요...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(err)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("다시 시도") {
                Task { await vm.fetchList() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(32)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text("추천 코스가 없어요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("처음으로") { vm.reset() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(32)
    }

    // MARK: - Top 3 List

    private var courseListContent: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(alignment: .leading, spacing: 4) {
                Text("당신을 위한 \(vm.courseList.count)가지 코스")
                    .font(.title2.weight(.bold))
                Text("마음에 드는 코스를 골라 탐험을 시작해보세요")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
                    Image(systemName: "arrow.counterclockwise")
                    Text("취향 다시 고르기")
                }
                .font(.callout.weight(.medium))
                .foregroundColor(.secondary)
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
        case 1: return .orange
        case 2: return Color.orange.opacity(0.75)
        default: return Color.orange.opacity(0.55)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // 헤더: 순위 + 제목
                HStack(alignment: .top, spacing: 10) {
                    Text("\(rank)")
                        .font(.callout.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(rankColor)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.title.isEmpty ? "이름 없는 코스" : course.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                            Text("\(course.durationDays)일 일정")
                            Text("·")
                            Image(systemName: "mappin.and.ellipse")
                            Text("\(course.places.count)곳")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                // 대표 장소 칩
                if !previewPlaceNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(previewPlaceNames, id: \.self) { name in
                            Text(name)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                        if course.places.count > previewPlaceNames.count {
                            Text("+\(course.places.count - previewPlaceNames.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
