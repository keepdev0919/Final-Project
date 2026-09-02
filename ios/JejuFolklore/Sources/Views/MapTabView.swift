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
        VStack(spacing: 0) {
            PixelTopBar(title: "지도")
            countLine
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
    private var countLine: some View {
        HStack(spacing: PixelSpacing.xs) {
            PixelIcon(.target, size: 16, color: PixelColor.inkWeak)
            if vm.isLoading && vm.pins.isEmpty {
                Text("불러오는 중…")
                    .font(PixelFont.label).foregroundStyle(PixelColor.inkWeak)
            } else {
                Text("\(vm.activeCount)곳 플레이 가능 · \(vm.preparingCount)곳 준비 중")
                    .font(PixelFont.label).foregroundStyle(PixelColor.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.top, PixelSpacing.m)
    }

    /// 핀 뜻풀이. **색만으로 구분하지 않는다** — 모양도 다르다 (DESIGN.md §7).
    private var legend: some View {
        HStack(spacing: PixelSpacing.l) {
            legendItem(color: PixelColor.primary, filled: true, text: "플레이 가능")
            legendItem(color: PixelColor.locked, filled: false, text: "준비 중")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.vertical, PixelSpacing.s)
    }

    private func legendItem(color: Color, filled: Bool, text: String) -> some View {
        HStack(spacing: PixelSpacing.xs) {
            Rectangle()
                .fill(filled ? color : Color.clear)
                .frame(width: 12, height: 12)
                .overlay(Rectangle().stroke(PixelColor.ink, lineWidth: 2))
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

    private func chip(_ target: JejuMapFocus, title: String) -> some View {
        let on = focus == target
        return Button {
            focus = target
            selected = nil
        } label: {
            PixelChip(text: title,
                      fill: on ? PixelColor.primary : PixelColor.surface,
                      label: on ? PixelColor.onPrimary : PixelColor.ink)
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
