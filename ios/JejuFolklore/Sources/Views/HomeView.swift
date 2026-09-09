import SwiftUI

/// 퀘스트 탭 — **게임으로 들어가는 화면**.
///
/// 시안(2026-09-02) 그대로다.
///
///     [!] 관광지를 플레이하세요
///         제주 관광지 하나가 통째로 게임 속 장소가 됩니다…
///
///     📖 수행 가능한 퀘스트
///     ────────────────────
///     [퀘스트 카드 × 5]
///
/// 무엇이 뜨는지는 서버 `data/places.json` 의 상태가 정한다 —
/// `LIVE` 는 퀘스트 카드, `PLANNED` 는 준비 중 카드, `CANDIDATE` 는 안 뜬다.
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    @State private var selectedPlay: PlaySummary?
    @State private var selectedPlace: PlayMapPin?

    var body: some View {
        // 시안에 상단바가 없다. 「놀멍봅서」 바를 넣었던 것은 「웹 목업엔 상태바가
        // 없으니 아이폰에선 필요하다」는 내 추측이었다 — SwiftUI 가 상태바 자리를
        // 알아서 비운다. 시안대로 뺐다(2026-09-03).
        ScrollView {
            VStack(alignment: .leading, spacing: PixelSpacing.sectionGap) {
                introCard
                questSection
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.top, PixelSpacing.xl)
            // ⚠️ 직접 만든 탭바는 ScrollView 가 알지 못한다. 하단 여백을 주지 않으면
            // 마지막 카드가 탭바에 가린다(2026-08-20에 실제로 겪음).
            .padding(.bottom, PixelSpacing.xxxl)
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(item: $selectedPlay) { play in
            PlayDetailView(playId: play.id)
        }
        // PLAY 상세·현장에서 돌아왔을 때 카드 문구를 새로 읽는다 —
        // 「퀘스트 수락」이 「이어서 하기」·「다시 하기」로 바뀌는 시점이다.
        .onChange(of: selectedPlay) { if selectedPlay == nil { vm.refreshProgress() } }
        .navigationDestination(item: $selectedPlace) { pin in
            PlaceDetailView(place: CoursePlace(name: pin.placeName, lat: pin.lat,
                                               lng: pin.lng, day: 0))
        }
        .task { await vm.load() }
        .refreshable { await vm.load(force: true) }
    }

    // MARK: - 인트로

    /// 이 앱이 뭘 하는 물건인지 한 번에 말한다.
    ///
    /// 항상 띄운다(2026-09-02 조익준님 결정). 처음 여는 사람이 「퀘스트」라는 말만
    /// 보고는 관광 앱인지 게임인지 모른다.
    private var introCard: some View {
        // 코스·지도 탭과 **같은 부품**을 쓴다 (`PixelIntroCard`, 2026-09-09).
        // 이 화면의 모양은 그대로다 — 세 탭이 같은 틀을 쓰게 만든 것뿐이다.
        PixelIntroCard(
            icon: .bang,
            iconColor: PixelColor.primaryContainer,
            // 「플레이」와 「클리어」만 강조색. 두 낱말이 이 앱의 전부다.
            title: Text("관광지를 ")
                + Text("플레이").foregroundColor(PixelColor.primaryContainer)
                + Text("하세요"),
            message: Text("제주 관광지 하나가 통째로 게임 속 장소가 됩니다. 실제 장소를 돌아다니며 미션을 수행하고 그곳을 ")
                + Text("클리어").foregroundColor(PixelColor.primaryContainer)
                    .font(PixelFont.bodyLargeBold)
                + Text("하세요.")
        )
    }

    // MARK: - 퀘스트 목록

    @ViewBuilder
    private var questSection: some View {
        VStack(alignment: .leading, spacing: PixelSpacing.cardGap) {
            // 시안: 아이콘만 초록, 제목은 잉크, 밑줄은 잉크 4px.
            // 이 모양을 `PixelSectionHeader` 로 뽑았다 (2026-09-09) — 코스 탭 두
            // 섹션이 같은 머리를 쓰게 되면서 두 파일에 같은 그림이 생겼었다.
            PixelSectionHeader(title: "수행 가능한 퀘스트", icon: .map,
                               iconColor: PixelColor.primaryContainer,
                               underline: PixelSpacing.borderHeavy)

            if vm.isLoading && vm.pins.isEmpty {
                loadingRow
            } else if vm.pins.isEmpty {
                emptyRow
            } else {
                ForEach(vm.pins) { pin in
                    if let play = pin.play {
                        PlayCard(play: play, progressText: vm.progressText(for: play.id)) {
                            selectedPlay = play
                        }
                    } else {
                        PreparingPlaceCard(placeName: pin.placeName,
                                           coverName: pin.placeKey,
                                           thumbnail: pin.thumbnail) {
                            selectedPlace = pin
                        }
                    }
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
        .padding(.vertical, PixelSpacing.xxxl)
    }

    private var emptyRow: some View {
        VStack(spacing: PixelSpacing.s) {
            PixelIcon(.warn, size: 40, color: PixelColor.locked)
            Text("퀘스트를 불러오지 못했어요.")
                .font(PixelFont.body)
                .foregroundStyle(PixelColor.inkWeak)
            Text("아래로 당겨 다시 시도해보세요.")
                .font(PixelFont.labelSmall)
                .foregroundStyle(PixelColor.inkWeak)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PixelSpacing.xxxl)
    }
}

// MARK: - 뷰모델

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [PlayMapPin] = []
    @Published var isLoading = false
    private var progressLabels: [String: String] = [:]

    func load(force: Bool = false) async {
        if !force && !pins.isEmpty { refreshProgress(); return }
        isLoading = true
        defer { isLoading = false }
        let result = try? await PlayAPI.mapPins()
        // 지도에는 다 뜨지만 홈 퀘스트 카드는 `homeVisible` 인 곳만 —
        // 콘텐츠 제작에 아직 착수하지 않은 후보지까지 퀘스트로 보이면 안 된다.
        // 플레이할 수 있는 것부터. 같은 상태 안에서는 서버 순서를 지킨다.
        pins = (result?.pins ?? []).filter(\.homeVisible).sorted { a, b in
            a.status == .active && b.status != .active
        }
        refreshProgress()
    }

    /// 카드 버튼에 쓸 문구. 손 안 댄 퀘스트는 nil 이라 「퀘스트 수락」이 뜬다.
    func progressText(for playId: String) -> String? { progressLabels[playId] }

    func refreshProgress() {
        var map: [String: String] = [:]
        for p in PlayProgressStore.shared.inProgress() { map[p.playId] = "이어서 하기" }
        for p in PlayProgressStore.shared.completed() { map[p.playId] = "다시 하기" }
        progressLabels = map
    }
}
