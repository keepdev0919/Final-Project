import SwiftUI

/// 홈 — **PLAY 로 들어가는 화면**이다 (`CLAUDE.md` 제품 구조).
///
/// 장소 목록이 아니다. 「제주 둘러보기」 같은 섹션을 기본 구조로 두지 않는다.
/// 지금 플레이할 수 있는 PLAY 를 맨 위에 두고, 준비 중인 곳을 아래에 둔다.
///
/// 무엇이 뜨는지는 서버 `data/places.json` 의 상태가 정한다 —
/// `LIVE` 는 PLAY 카드, `PLANNED` 는 준비 중 카드, `CANDIDATE` 는 안 뜬다.
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    @State private var selectedPlay: PlaySummary?
    @State private var selectedPlace: PlayMapPin?

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "놀멍봅서", isAppName: true)

            ScrollView {
                VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                    if vm.isLoading && vm.pins.isEmpty {
                        loadingRow
                    } else if vm.pins.isEmpty {
                        emptyRow
                    } else {
                        playSection
                        preparingSection
                    }
                }
                .padding(.horizontal, PixelSpacing.screenMargin)
                .padding(.top, PixelSpacing.xxl)
                // ⚠️ 직접 만든 탭바는 ScrollView 가 알지 못한다. 하단 여백을 주지 않으면
                // 마지막 카드가 탭바에 가린다(2026-08-20에 실제로 겪음).
                .padding(.bottom, PixelSpacing.xxxl)
            }
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(item: $selectedPlay) { play in
            PlayDetailView(playId: play.id)
        }
        .navigationDestination(item: $selectedPlace) { pin in
            PlaceDetailView(place: CoursePlace(name: pin.placeName, lat: pin.lat,
                                               lng: pin.lng, day: 0))
        }
        .task { await vm.load() }
        .refreshable { await vm.load(force: true) }
    }

    // MARK: - 플레이할 수 있는 것

    @ViewBuilder
    private var playSection: some View {
        let active = vm.pins.filter { $0.status == .active }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                PixelSectionHeader(title: "지금 플레이할 수 있어요", icon: .target)
                ForEach(active) { pin in
                    if let play = pin.play {
                        PlayCard(play: play, progressText: vm.progressText(for: play.id)) {
                            selectedPlay = play
                        }
                    }
                }
            }
        }
    }

    // MARK: - 준비 중

    @ViewBuilder
    private var preparingSection: some View {
        let waiting = vm.pins.filter { $0.status == PlayMapPin.Status.preparing }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
                PixelSectionHeader(title: "곧 열려요", icon: .clock,
                                   accent: PixelColor.secondary)
                ForEach(waiting) { pin in
                    PreparingPlaceCard(placeName: pin.placeName) { selectedPlace = pin }
                }
            }
        }
    }

    // MARK: - 비었을 때

    private var loadingRow: some View {
        VStack(spacing: PixelSpacing.m) {
            ProgressView()
            Text("불러오는 중…")
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PixelSpacing.xxxl)
    }

    private var emptyRow: some View {
        VStack(spacing: PixelSpacing.s) {
            PixelIcon(.warn, size: 40, color: PixelColor.locked)
            Text("PLAY 를 불러오지 못했어요.")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
            Text("아래로 당겨 다시 시도해보세요.")
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PixelSpacing.xxxl)
    }
}

// MARK: - 뷰모델

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [PlayMapPin] = []
    @Published var isLoading = false

    /// 「생활기록 4 / 6」. 진행 중인 PLAY 만 값이 있다.
    private var progressLabels: [String: String] = [:]

    func load(force: Bool = false) async {
        if !force && !pins.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        let result = try? await PlayAPI.mapPins()
        // 활성 → 준비 중 순으로. 같은 상태 안에서는 서버 순서를 지킨다.
        pins = (result?.pins ?? []).sorted { a, b in
            a.status == .active && b.status != .active
        }
        refreshProgress()
    }

    func progressText(for playId: String) -> String? { progressLabels[playId] }

    /// 저장된 진행을 읽어 카드 도장에 쓸 문구를 만든다.
    ///
    /// 기록 칸의 **총 개수는 PLAY 상세를 열어야 알 수 있다.** 홈에서 전부
    /// 받아오면 목록 하나에 PLAY 전체를 딸려오게 하는 셈이라, 여기서는
    /// 「이어서 하기」만 알린다.
    private func refreshProgress() {
        var map: [String: String] = [:]
        for p in PlayProgressStore.shared.inProgress() {
            map[p.playId] = "이어서 하기"
        }
        for p in PlayProgressStore.shared.completed() {
            map[p.playId] = "CLEAR"
        }
        progressLabels = map
    }
}
