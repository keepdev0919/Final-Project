import SwiftUI

// MARK: - TasteDiscoveryView

struct TasteDiscoveryView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var step = 0
    @State private var selectedMood = ""
    @State private var selectedPlace = ""
    @State private var selectedDays = 1
    @State private var navigateToPreview = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    progressBar

                    Group {
                        switch step {
                        case 0: moodStep
                        case 1: placeStep
                        case 2: daysStep
                        case 3: transportStep
                        default: EmptyView()
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    Spacer()
                }

                if vm.isLoading {
                    LoadingOverlay(step: vm.loadingStep)
                }
            }
            .animation(.spring(response: 0.35), value: step)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToPreview) {
                if let course = vm.result {
                    CoursePreviewView(course: course)
                        .onDisappear { vm.reset() }
                }
            }
            .onChange(of: vm.result) { course in
                if course != nil {
                    navigateToPreview = true
                    step = 0
                    selectedMood = ""
                    selectedPlace = ""
                }
            }
            .alert("코스를 만들지 못했어요", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("다시 시도") { Task { await generate(transport: vm.transport) } }
                Button("처음으로", role: .cancel) { resetToStart() }
            } message: {
                Text(vm.errorMessage ?? "네트워크를 확인하고 다시 시도해주세요.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                Text("\(step + 1) / 4")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("제주 여행 코스 만들기")
                    .font(.title3.weight(.bold))
                Text("설화 기반 제주스러운 코스를 추천해드릴게요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.12))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * CGFloat(step + 1) / 4)
                    .animation(.spring(response: 0.4), value: step)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Steps

    private var moodStep: some View {
        DiscoveryStep(
            question: "어떤 분위기가 끌려요?",
            options: [
                ("🌙", "신비롭고 으스스한"),
                ("🌸", "따뜻하고 감동적인"),
                ("⛩️", "웅장하고 신성한"),
                ("🎣", "사람들의 삶 이야기"),
            ]
        ) { label in
            selectedMood = label
            withAnimation { step = 1 }
        }
    }

    private var placeStep: some View {
        DiscoveryStep(
            question: "주로 어디가 좋아요?",
            options: [
                ("🌊", "바다"),
                ("🌿", "오름·산"),
                ("🏘️", "마을"),
                ("✨", "상관없어요"),
            ]
        ) { label in
            selectedPlace = label
            withAnimation { step = 2 }
        }
    }

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("며칠이에요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            HStack(spacing: 10) {
                ForEach([(1, "1일"), (2, "2일"), (3, "3일"), (5, "4일+")], id: \.0) { days, label in
                    Button {
                        selectedDays = days
                        withAnimation { step = 3 }
                    } label: {
                        Text(label)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var transportStep: some View {
        DiscoveryStep(
            question: "이동수단은요?",
            options: [
                ("🚗", "렌트카"),
                ("🚶", "대중교통·도보"),
            ]
        ) { label in
            let transport = label == "렌트카" ? "car" : "walk"
            Task { await generate(transport: transport) }
        }
    }

    // MARK: - Actions

    private func generate(transport: String) async {
        let theme = CourseRecommendViewModel.mapTheme(mood: selectedMood, place: selectedPlace)
        vm.selectedTheme = theme
        vm.durationDays = selectedDays
        vm.transport = transport
        await vm.recommend()
    }

    private func resetToStart() {
        step = 0
        selectedMood = ""
        selectedPlace = ""
        selectedDays = 1
        vm.reset()
    }
}

// MARK: - DiscoveryStep (재사용 컴포넌트)

private struct DiscoveryStep: View {
    let question: String
    let options: [(icon: String, label: String)]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(options, id: \.label) { option in
                    Button { onSelect(option.label) } label: {
                        HStack(spacing: 16) {
                            Text(option.icon)
                                .font(.title2)
                                .frame(width: 36)
                            Text(option.label)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
