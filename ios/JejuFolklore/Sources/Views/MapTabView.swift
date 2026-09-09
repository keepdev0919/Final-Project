import SwiftUI
import GoogleMaps
import CoreLocation

/// 지도 탭 — **제주 어디에서 PLAY 할 수 있고, 앞으로 어디에 생기는가**를 보여준다.
///
/// ## 답하는 질문이 바뀌었다 (2026-09-02)
///
///     전: "제주에 오디 해설이 몇 개 있나"          → 핀 121개
///     후: "어디서 놀멍봅서를 할 수 있고 어디에 생기나" → 활성 + 준비 중
///
/// 오디에 장소가 있다는 이유만으로 공개 지도에 띄우지 않는다 (`데이터.md` §11).
/// 무엇이 뜨는지는 서버 `data/places.json` 의 상태가 정한다 —
/// `LIVE` 는 활성 핀, `PLANNED` 는 준비 중 핀, `CANDIDATE` 는 안 뜬다.
struct MapTabView: View {
    @StateObject private var vm = PlayMapViewModel()
    @State private var selected: PlayMapPin?
    @State private var pushedPlay: PlaySummary?
    @State private var pushedPlace: PlayMapPin?
    @State private var focus: JejuMapFocus = .wholeIsland

    var body: some View {
        // ⚠️ 상단바를 두지 않는다 — 퀘스트·코스 탭과 같다 (2026-09-09 조익준님 결정).
        VStack(spacing: 0) {
            introCard
            legend
            regionChips
            mapArea
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(item: $pushedPlay) { play in
            PlayDetailView(playId: play.id)
        }
        .navigationDestination(item: $pushedPlace) { pin in
            PlaceDetailView(place: CoursePlace(name: pin.placeName, lat: pin.lat,
                                               lng: pin.lng, day: 0))
        }
        .task { await vm.load() }
    }

    // MARK: - 개수

    /// 숫자를 **서버가 준 값 그대로** 쓴다. 화면에 박아두면 PLAY 가 늘어날 때
    /// 조용히 거짓이 된다 — 「여행자 N명」과 같은 종류의 실수다.
    /// 퀘스트·코스 탭과 같은 머리말 카드. 전에는 「N곳 플레이 가능 · M곳 준비 중」
    /// 한 줄만 덩그러니 있었는데, 그 숫자를 설명 문장 안으로 넣었다.
    ///
    /// 지도 탭의 색은 **파랑**이다 — 시안이 파랑에 「하늘·물·길찾기」를 맡겨 뒀다.
    /// 잉크 블록에는 밝은 파랑, 글자 강조에는 진한 파랑을 쓴다.
    private var introCard: some View {
        PixelIntroCard(
            icon: .mapPin,
            iconColor: PixelColor.secondaryContainer,
            // 「플레이할까요」가 아니라 **「열렸을까요」**다 (2026-09-09 조익준님 결정).
            // 이 지도에는 아직 플레이할 수 없는 `준비 중` 핀이 같이 뜬다. 제목이
            // 「플레이할까요」면 화면 절반을 설명하지 못해, 사용자가 빈 핀을 눌러보고
            // 나서야 안 되는 곳임을 알게 된다. 「열림」은 `LIVE`/`PLANNED` 두 상태를
            // 한 낱말로 덮으면서 게임 말이기도 하다 (색 이름도 이미 `locked` 다).
            //
            // 코스 탭이 「어느 쪽으로 떠날까요」라 「제주 어디서…할까요」를 그대로 두면
            // 두 탭이 똑같이 방향을 묻는 것처럼 들렸다.
            title: Text("제주 어디가 ")
                + Text("열렸을까요").foregroundColor(PixelColor.secondary),
            message: countMessage
        )
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.top, PixelSpacing.m)
        .padding(.bottom, PixelSpacing.l)
    }

    private var countMessage: Text {
        if vm.isLoading && vm.pins.isEmpty {
            return Text("열린 곳을 불러오는 중이에요")
        }
        // 숫자가 먼저 온다. 「열리는 중」만 있으면 아직 덜 만든 서비스로 읽힐 수
        // 있는데, 「지금 N곳이 열렸고」가 앞에 서면 지금 할 수 있는 일이 먼저 보인다.
        return Text("지금 ")
            + Text("\(vm.activeCount)곳").foregroundColor(PixelColor.secondary)
            + Text("이 열렸고, ")
            + Text("\(vm.preparingCount)곳").foregroundColor(PixelColor.secondary)
            + Text("이 곧 열려요")
    }

    /// 핀 뜻풀이. **색만으로 구분하지 않는다** — 모양도 다르다.
    ///
    /// ⚠️ 머리말은 「열림」인데 범례는 「플레이 가능 / 준비 중」이다. 일부러 그대로
    /// 뒀다 (2026-09-09 조익준님 결정) — 머리말 낱말만 먼저 바꿔 보고, 범례까지
    /// 「열림 / 곧 열림」으로 맞출지는 실제 화면을 보고 정한다.
    /// 핀 뜻풀이와 권역 고르기를 **한 줄씩 나란히** 둔다.
    ///
    /// 전에는 범례가 제 줄, 칩이 제 줄로 따로 놀았다. 범례는 「지도를 읽는 법」이라
    /// 작게 붙어 있으면 되고, 고르는 칩이 주인이다.
    private var legend: some View {
        HStack(spacing: PixelSpacing.l) {
            legendItem(color: PixelColor.primary, filled: true, text: "플레이 가능")
            legendItem(color: PixelColor.locked, filled: false, text: "준비 중")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.bottom, PixelSpacing.s)
    }

    /// **색만으로 구분하지 않는다** — 모양(채움/빈칸)도 다르다.
    private func legendItem(color: Color, filled: Bool, text: String) -> some View {
        HStack(spacing: PixelSpacing.xs) {
            Rectangle()
                .fill(filled ? color : PixelColor.surface)
                .frame(width: 12, height: 12)
                .overlay(Rectangle().stroke(PixelColor.ink, lineWidth: PixelSpacing.border))
            Text(text).font(PixelFont.labelSmall).foregroundStyle(PixelColor.inkWeak)
        }
    }

    // MARK: - 지역 칩

    private var regionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PixelSpacing.s) {
                chip(.wholeIsland, title: "전체")
                ForEach(JejuRegionDef.all, id: \.id) { region in
                    chip(.region(region.id), title: region.label)
                }
            }
            .padding(.horizontal, PixelSpacing.screenMargin)
            .padding(.bottom, PixelSpacing.m)
        }
    }

    /// 고른 권역은 **그 권역의 색**이다 — 코스 탭 권역 버튼·코스 카드 배지와 같다
    /// (2026-09-09 조익준님 결정). 전에는 금색 하나였고, 그 전에는 초록이라
    /// 범례의 「플레이 가능」 초록과 헷갈렸다.
    private func chip(_ target: JejuMapFocus, title: String) -> some View {
        let on = focus == target
        let c = JejuRegionDef.colors(for: title)
        return Button {
            focus = target
            selected = nil
        } label: {
            PixelChip(text: title,
                      fill: on ? c.fill : PixelColor.surface,
                      label: on ? c.on : PixelColor.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: - 지도 + 미니 카드

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            PlayPinMap(pins: vm.pins, focus: focus, selected: $selected)
                .pixelBorder()

            if let pin = selected {
                PlayMapCard(
                    pin: pin,
                    onClose: { selected = nil },
                    onOpen: {
                        if let play = pin.play { pushedPlay = play } else { pushedPlace = pin }
                    }
                )
                .padding(PixelSpacing.m)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.default, value: selected)
    }
}

// MARK: - 미니 카드

/// 핀을 눌렀을 때 아래에서 올라오는 카드.
///
/// 활성이면 **PLAY 정보**를, 준비 중이면 장소 이름과 「준비 중」을 보여준다.
/// 오디 해설 분량(「해설 10개 · 6분 53초」)은 더 이상 쓰지 않는다 —
/// 사용자가 궁금한 것은 해설 길이가 아니라 여기서 뭘 할 수 있는가다.
struct PlayMapCard: View {
    let pin: PlayMapPin
    let onClose: () -> Void
    let onOpen: () -> Void

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: PixelSpacing.m) {
                HStack(alignment: .top, spacing: PixelSpacing.m) {
                    thumbnail
                    VStack(alignment: .leading, spacing: PixelSpacing.xs) {
                        Text(pin.placeName)
                            .font(PixelFont.sectionTitle)
                            .foregroundStyle(PixelColor.ink)
                            .multilineTextAlignment(.leading)
                        if let play = pin.play {
                            Text(play.title)
                                .font(PixelFont.body)
                                .foregroundStyle(PixelColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(play.durationText) · \(play.distanceText) · \(play.missionCount) Missions")
                                .font(PixelFont.labelSmall)
                                .foregroundStyle(PixelColor.inkWeak)
                        } else {
                            PixelChip(text: "PLAY 준비 중", icon: .lock,
                                      fill: PixelColor.locked, label: PixelColor.onLocked)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        PixelIcon(.close, size: 24, color: PixelColor.inkWeak)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("닫기")
                }
                PixelButton(title: pin.play != nil ? "PLAY 보기" : "장소 정보 보기",
                            style: pin.play != nil ? .primary : .plain,
                            action: onOpen)
            }
            .padding(PixelSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            PixelColor.surfaceHigh
            if let s = pin.play?.thumbnail, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFill()
                    default: PixelIcon(.photo, size: 24, color: PixelColor.inkWeak)
                    }
                }
            } else {
                PixelIcon(pin.play != nil ? .photo : .lock, size: 24, color: PixelColor.inkWeak)
            }
        }
        .frame(width: 72, height: 72)
        .clipped()
        .pixelBorder()
        .accessibilityHidden(true)
    }
}

// MARK: - 카메라 목표

enum JejuMapFocus: Equatable {
    case wholeIsland
    case region(String)

    private static let islandBounds = (
        southWest: CLLocationCoordinate2D(latitude: 33.10, longitude: 126.12),
        northEast: CLLocationCoordinate2D(latitude: 33.58, longitude: 126.98)
    )

    /// 권역 경계는 `JejuRegionDef` 가 정한다 — 코스 탭과 같은 기준을 써야
    /// "동부에서 고른 코스"와 "지도의 동부"가 어긋나지 않는다.
    var bounds: GMSCoordinateBounds {
        switch self {
        case .wholeIsland:
            return GMSCoordinateBounds(coordinate: Self.islandBounds.southWest,
                                       coordinate: Self.islandBounds.northEast)
        case .region(let id):
            let coords = JejuRegionDef.find(id)?.polygonCoords ?? []
            guard !coords.isEmpty else { return JejuMapFocus.wholeIsland.bounds }
            return coords.reduce(GMSCoordinateBounds()) { $0.includingCoordinate($1) }
        }
    }
}

// MARK: - 뷰모델

@MainActor
final class PlayMapViewModel: ObservableObject {
    @Published var pins: [PlayMapPin] = []
    @Published var activeCount = 0
    @Published var preparingCount = 0
    @Published var isLoading = false

    func load() async {
        guard pins.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await PlayAPI.mapPins() else { return }
        pins = result.pins
        activeCount = result.activeCount
        preparingCount = result.preparingCount
    }
}
