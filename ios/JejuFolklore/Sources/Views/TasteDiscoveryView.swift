import SwiftUI

// MARK: - TasteDiscoveryView

struct TasteDiscoveryView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var step = 0
    @State private var selectedRegion = ""
    @State private var selectedStyle = ""
    @State private var selectedDays = 1
    @State private var navigateToList = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    progressBar

                    Group {
                        switch step {
                        case 0: regionStep
                        case 1: styleStep
                        case 2: daysStep
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

                if vm.isLoadingList {
                    LoadingOverlay(step: vm.loadingStep)
                }
            }
            .animation(.spring(response: 0.35), value: step)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToList) {
                CourseListView(vm: vm)
                    .onDisappear {
                        if vm.courseList.isEmpty { vm.reset() }
                    }
            }
            .onChange(of: vm.courseList) {
                if !vm.courseList.isEmpty {
                    navigateToList = true
                }
            }
            .alert("코스를 가져오지 못했어요", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("다시 시도") { Task { await startSearch() } }
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

                Text("\(step + 1) / 3")
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
                Text("실제 여행자들의 검증된 경로로 코스를 추천해드릴게요")
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
                    .frame(width: geo.size.width * CGFloat(step + 1) / 3)
                    .animation(.spring(response: 0.4), value: step)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Step 1: 지역 선택 (제주도 지도)

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("어느 지역을 여행하고 싶어요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            JejuMapRegionPicker { region in
                selectedRegion = region
                withAnimation { step = 1 }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 2: 스타일 선택 (이미지 카드)

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("어떤 여행 스타일이에요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(StyleCard.all) { card in
                    StyleCardView(card: card) {
                        selectedStyle = card.key
                        withAnimation { step = 2 }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 3: 기간 선택

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
                        Task { await startSearch() }
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

    // MARK: - Actions

    private func startSearch() async {
        vm.selectedRegion = selectedRegion
        vm.selectedStyle = selectedStyle
        vm.durationDays = selectedDays
        await vm.fetchList()
    }

    private func resetToStart() {
        step = 0
        selectedRegion = ""
        selectedStyle = ""
        selectedDays = 1
        vm.reset()
    }
}

// MARK: - 제주 지도 지역 선택 컴포넌트

private struct JejuMapRegionPicker: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 북부 (제주시)
            regionButton("북부 (제주시)", color: .blue.opacity(0.15), icon: "🏙️") { onSelect("북부") }

            // 중간 행: 서부 | 전체 | 동부
            HStack(spacing: 8) {
                regionButton("서부", color: .green.opacity(0.15), icon: "🌿") { onSelect("서부") }
                regionButton("전체", color: .orange.opacity(0.15), icon: "🗺️") { onSelect("전체") }
                    .frame(maxWidth: .infinity)
                regionButton("동부", color: .purple.opacity(0.15), icon: "🌅") { onSelect("동부") }
            }

            // 남부 (서귀포)
            regionButton("남부 (서귀포)", color: .red.opacity(0.15), icon: "🌊") { onSelect("남부") }
        }
    }

    private func regionButton(_ label: String, color: Color, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(icon)
                    .font(.title3)
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StyleCard

private struct StyleCard: Identifiable {
    let id = UUID()
    let label: String
    let key: String          // 백엔드 전달값
    let imageName: String

    static let all: [StyleCard] = [
        StyleCard(label: "자연·오름",  key: "nature",  imageName: "mood_grand_sacred"),
        StyleCard(label: "해변·바다",  key: "ocean",   imageName: "mood_village"),
        StyleCard(label: "맛집·카페",  key: "food",    imageName: "mood_cheerful"),
        StyleCard(label: "문화·역사",  key: "culture", imageName: "mood_mysterious"),
    ]
}

// MARK: - StyleCardView

private struct StyleCardView: View {
    let card: StyleCard
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                Image(card.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(card.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
