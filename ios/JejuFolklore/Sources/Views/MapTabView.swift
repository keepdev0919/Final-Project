import SwiftUI
import GoogleMaps
import CoreLocation

/// 지도 탭 — **우리가 가진 콘텐츠가 몇 개인지 한눈에 보여주는 화면** (`docs/공고.md` §3 P0-3).
///
/// 길을 찾는 도구가 아니다. 「이 앱에 제주 게임 콘텐츠가 그래서 몇 개 있는 거지?」를
/// 지도 한 장으로 답하는 것이 목적이다. 그래서 세 가지를 지킨다.
///
/// 1. **핀을 다 띄운다.** 일부만 보여주면 목적이 깨진다
/// 2. **개수를 글자로도 적는다.** 핀만 뿌리면 사용자가 세야 한다
/// 3. **지역 칩은 걸러내지 않고 카메라만 옮긴다.** 걸러내면 「전체가 몇 개」가 안 보인다
///
/// 핀은 전부 같은 모양이다. 홈의 세계관 라벨 6종으로 구분하는 안을 검토했지만
/// 103곳을 사람이 분류해야 하고(자동 분류는 무르다 — `data/home_stage.json` 설명 참조),
/// 「양이 많다」는 인상은 같은 모양일 때 가장 세다.
struct MapTabView: View {
    @StateObject private var vm = MapViewModel()
    @State private var selected: MapPlace?
    @State private var pushed: MapPlace?
    /// 카메라를 옮길 목표. 지역 칩을 누르면 바뀐다.
    @State private var focus: JejuMapFocus = .wholeIsland

    var body: some View {
        VStack(spacing: 0) {
            PixelTopBar(title: "지도")
            countLine
            regionChips
            mapArea
        }
        .background(PixelColor.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(item: $pushed) { place in
            PlaceDetailView(place: place.asCoursePlace)
        }
        .task { await vm.load() }
    }

    // MARK: - 개수 한 줄

    /// 숫자를 **서버가 준 개수 그대로** 쓴다. 화면에 박아두면 오디 목록이 늘어날 때
    /// 조용히 거짓이 된다 — 「여행자 N명」과 같은 종류의 실수다.
    private var countLine: some View {
        HStack(spacing: PixelSpacing.xs) {
            PixelIcon(.headphone, size: 16, color: PixelColor.inkWeak)
            if vm.places.isEmpty {
                Text(vm.isLoading ? "불러오는 중…" : "아직 없어요")
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.inkWeak)
            } else {
                Text("제주에서 들을 수 있는 곳 \(vm.places.count)곳")
                    .font(PixelFont.label)
                    .foregroundStyle(PixelColor.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PixelSpacing.screenMargin)
        .padding(.vertical, PixelSpacing.m)
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
            // 지역을 옮기면 열려 있던 미니 카드는 닫는다 — 화면 밖의 장소 카드가
            // 남아 있으면 지금 보고 있는 지역과 안 맞는다.
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
            JejuPinMap(places: vm.places, focus: focus, selected: $selected)
                .pixelBorder()

            if let place = selected {
                // 미니 카드는 화면 아래쪽만 덮는다. **지도와 눌린 핀이 계속 보여야 한다** —
                // 핀을 누르는 것은 미리보기이고, 넘어가는 것은 버튼을 눌렀을 때뿐이다.
                MapPlaceCard(
                    place: place,
                    onClose: { selected = nil },
                    onOpen: { pushed = place }
                )
                .padding(PixelSpacing.m)
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.default, value: selected)
    }
}

// MARK: - 카메라 목표

/// 지도를 어디에 맞출지. **핀을 걸러내지 않는다** — 카메라만 옮긴다.
enum JejuMapFocus: Equatable {
    case wholeIsland
    case region(String)

    /// 제주 전역이 한 화면에 들어오는 경계.
    private static let islandBounds = (
        southWest: CLLocationCoordinate2D(latitude: 33.10, longitude: 126.12),
        northEast: CLLocationCoordinate2D(latitude: 33.58, longitude: 126.98)
    )

    /// 카메라가 담아야 할 사각형. 권역 경계는 `JejuRegionDef`가 정한다 —
    /// 코스 탭과 같은 기준을 쓰려면 여기서 좌표를 새로 적으면 안 된다.
    var bounds: GMSCoordinateBounds {
        switch self {
        case .wholeIsland:
            return GMSCoordinateBounds(coordinate: Self.islandBounds.southWest,
                                       coordinate: Self.islandBounds.northEast)
        case .region(let id):
            let coords = JejuRegionDef.find(id)?.polygonCoords ?? []
            guard !coords.isEmpty else {
                return JejuMapFocus.wholeIsland.bounds
            }
            return coords.reduce(GMSCoordinateBounds()) { $0.includingCoordinate($1) }
        }
    }
}

// MARK: - 뷰모델

@MainActor
final class MapViewModel: ObservableObject {
    @Published var places: [MapPlace] = []
    @Published var isLoading = false

    func load() async {
        guard places.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        places = (try? await MapAPI.places()) ?? []
    }
}
