import SwiftUI

struct CourseRecommendView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var navigateToPreview = false

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    themeSection
                    durationSection
                    transportSection
                    recommendButton
                }
                .padding(20)
            }
            .navigationTitle("코스 추천")
            .navigationDestination(isPresented: $navigateToPreview) {
                if let course = vm.result {
                    CoursePreviewView(course: course)
                }
            }
            .overlay {
                if vm.isLoading || vm.loadingStep == .done {
                    LoadingOverlay(step: vm.loadingStep)
                }
            }
            .alert("오류", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("다시 시도") { Task { await vm.recommend() } }
                Button("취소", role: .cancel) { vm.reset() }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .onChange(of: vm.result) { course in
                if course != nil { navigateToPreview = true }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("어떤 이야기를 찾아가고 싶으세요?")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(vm.themes, id: \.self) { theme in
                    ThemeCard(title: theme, isSelected: vm.selectedTheme == theme) {
                        vm.selectedTheme = theme
                    }
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("여행 일수")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { day in
                    Button("\(day)일") {
                        vm.durationDays = day
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.durationDays == day ? .orange : .secondary)
                }
            }
        }
    }

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이동 수단")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach([("car", "car.fill", "자동차"), ("walk", "figure.walk", "도보")], id: \.0) { mode in
                    Button {
                        vm.transport = mode.0
                    } label: {
                        Label(mode.2, systemImage: mode.1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.transport == mode.0 ? .orange : .secondary)
                }
            }
        }
    }

    private var recommendButton: some View {
        Button {
            Task { await vm.recommend() }
        } label: {
            Text("코스 추천받기")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(vm.selectedTheme.isEmpty || vm.isLoading)
    }
}

// MARK: - ThemeCard
struct ThemeCard: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - LoadingOverlay
struct LoadingOverlay: View {
    let step: LoadingStep

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                if step != .done {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                }
                Text(step.rawValue)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
