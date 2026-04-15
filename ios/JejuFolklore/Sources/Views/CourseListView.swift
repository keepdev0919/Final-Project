import SwiftUI

struct CourseListView: View {
    @ObservedObject var vm: CourseRecommendViewModel
    @State private var navigateToPreview = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("추천 코스")
                            .font(.title2.weight(.bold))
                        Text("\(regionLabel) · \(styleLabel) · \(vm.durationDays)일")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    ForEach(vm.courseList) { item in
                        CourseCardView(item: item) {
                            Task { await vm.fetchDetail(courseId: item.id) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }

            if vm.isLoadingDetail {
                LoadingOverlay(step: vm.loadingStep)
            }
        }
        .navigationTitle("코스 선택")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToPreview) {
            if let course = vm.selectedCourse {
                CoursePreviewView(course: course)
                    .onDisappear { vm.selectedCourse = nil }
            }
        }
        .onChange(of: vm.selectedCourse) {
            if vm.selectedCourse != nil {
                navigateToPreview = true
            }
        }
        .alert("코스 정보를 가져오지 못했어요", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "다시 시도해주세요.")
        }
    }

    private var regionLabel: String { vm.selectedRegion.isEmpty ? "전체" : vm.selectedRegion }
    private var styleLabel: String {
        switch vm.selectedStyle {
        case "nature":  return "자연·오름"
        case "ocean":   return "해변·바다"
        case "food":    return "맛집·카페"
        case "culture": return "문화·역사"
        default:        return vm.selectedStyle
        }
    }
}

// MARK: - CourseCardView

private struct CourseCardView: View {
    let item: CourseListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text("\(item.durationDays)일")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                // 대표 장소 2~3개
                let previewPlaces = Array(item.places.prefix(3))
                HStack(spacing: 6) {
                    ForEach(Array(previewPlaces.enumerated()), id: \.offset) { idx, place in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(place.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if item.places.count > 3 {
                        Text("외 \(item.places.count - 3)곳")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Text("코스 보기")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
