import SwiftUI

struct CourseListView: View {
    @ObservedObject var vm: CourseRecommendViewModel
    @State private var navigateToPreview = false
    @State private var shouldLoadNext = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if vm.isLoadingList {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("AI가 코스를 추천하고 있어요...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let err = vm.errorMessage {
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
            } else if !vm.courseList.isEmpty {
                // Back 버튼으로 돌아온 경우 (세 액션 버튼 대신 기본 Back 사용)
                VStack(spacing: 12) {
                    Text("다른 코스를 탐색하려면\n처음부터 다시 시작해주세요.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("처음으로") { vm.reset() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .padding(32)
            }

            if vm.isLoadingDetail {
                LoadingOverlay(step: vm.loadingStep)
            }
        }
        .navigationTitle("코스 추천")
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
            // navigateToPreview가 false가 되는 시점 = 사용자가 실제로 뒤로 간 경우만
            // (PlaceDetailView로 앞으로 갈 때는 navigateToPreview가 변하지 않음)
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
}
