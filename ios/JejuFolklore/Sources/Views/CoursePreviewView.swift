import SwiftUI
import MapKit
import SwiftData

// MARK: - CoursePreviewView

struct CoursePreviewView: View {
    let course: Course
    /// 「담기」를 보여줄지. 이미 담아 둔 코스로 들어왔으면 숨긴다.
    var showsSaveButton: Bool = true
    /// 담아 둔 코스를 관리하는 동작. 「내 코스」에서 들어왔을 때만 준다
    /// (2026-09-10 조익준님 결정) — 담기도 탐험도 없어지면서 그 자리가 비었는데,
    /// 이미 담아 둔 코스에 할 일은 이름을 고치거나 빼는 것이다.
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @StateObject private var vm: CoursePreviewViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarVisibility) private var tabBar
    /// **늘 하루가 골라져 있다** (2026-09-09 조익준님 결정). 전에는 「전체」가
    /// 기본이라 지도에 사흘치 경로가 한꺼번에 그려졌고, 그러면 어느 선이 어느 날인지
    /// 알 수 없어 「경로를 본다」는 목적이 무너진다. `onAppear` 에서 첫날로 맞춘다.
    @State private var selectedDay: Int = 1
    @State private var selectedPlace: CoursePlace?

    init(course: Course,
         showsSaveButton: Bool = true,
         onRename: (() -> Void)? = nil,
         onDelete: (() -> Void)? = nil) {
        self.course = course
        self.showsSaveButton = showsSaveButton
        self.onRename = onRename
        self.onDelete = onDelete
        _vm = StateObject(wrappedValue: CoursePreviewViewModel(course: course))
    }

    // 전체 day 목록 (중복 제거, 정렬)
    private var days: [Int] {
        Array(Set(course.places.map { $0.day })).sorted()
    }

    // day 기준으로 장소 그룹핑
    private var placesByDay: [Int: [CoursePlace]] {
        Dictionary(grouping: course.places, by: { $0.day })
    }

    // 전체 장소 순서 유지한 indexed 배열 (지도 마커 번호용)
    private var indexedPlaces: [IndexedPlace] {
        course.places.enumerated().map { IndexedPlace(index: $0.offset, place: $0.element) }
    }

    var body: some View {
        // **위아래로 나눈 한 페이지**다 (2026-09-10 조익준님 결정).
        //
        // 전에는 지도가 화면 전체에 깔리고 그 위에 바텀시트가 떠 있었다. 시트를
        // 올리고 내릴 때마다 「시트가 지도를 얼마나 덮는지」를 재서 카메라를 다시
        // 맞췄고, 그때마다 번호 마커와 경로가 흔들렸다. 시트 높이도 그래서 260 으로
        // 박아 둬야 했다. 겹치지 않게 두면 잴 것이 없다 — 제목, 지도, Day 칩, 장소
        // 목록이 한 줄로 내려오고 페이지 전체가 함께 스크롤된다.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                courseMap
                if days.count > 1 {
                    dayTabBar
                        .padding(.top, PixelSpacing.l)
                }
                // 고른 하루만 보여준다. 위 칩이 이미 「Day 1」이라고 말하고 있어서
                // 섹션 머리(「Day 1 ────」)는 같은 말을 두 번 하는 자리가 됐다.
                DaySectionView(
                    day: selectedDay,
                    places: placesByDay[selectedDay] ?? [],
                    globalOffset: globalOffset(for: selectedDay),
                    onPlaceTap: { selectedPlace = $0 }
                )
                .padding(.top, PixelSpacing.m)
                .padding(.bottom, PixelSpacing.xxl)
            }
        }
        .background(PixelColor.background)
        .overlay(alignment: .top) {
            if let text = vm.toastText {
                toastView(text, isError: vm.toastIsError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: vm.toastText)
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        // 뒤로가기는 떠 있는 버튼 하나. 화면 이름은 아래 큰 제목이 말한다.
        .pixelFloatingBack(topInset: PixelSpacing.s)
        // 담기·이름 변경·삭제는 아래에 붙박이로 둔다 — 목록을 끝까지 내려야
        // 나오면 담을 마음이 든 순간에 버튼이 없다. PLAY 상세와 같은 방식.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsSaveButton || onRename != nil || onDelete != nil {
                actionButtons
            }
        }
        // 이 화면에서는 탭바도 내린다 — 장소 상세·PLAY 상세와 같은 방식.
        .onAppear {
            tabBar?.hide()
            if let first = days.first { selectedDay = first }
            // 이미 담긴 코스인지 저장소에 물어본다 — 화면 상태만 믿으면 나갔다
            // 다시 들어왔을 때 같은 코스를 또 담게 된다.
            vm.refreshSavedState(context: modelContext)
        }
        .onDisappear { tabBar?.show() }
    }

    // MARK: - Header

    /// **목록 카드와 같은 말을 같은 순서로** (2026-09-10 조익준님 결정).
    ///
    /// 큰 글자는 「성산일출봉 외 6곳」, 그 아래 칩 두 개가 권역과 일수를 맡는다.
    /// 전에는 서버 제목(「동부 2일 · 성산일출봉 외 6곳」)을 그대로 크게 쓰고
    /// 아래에 「2일 · 장소 9곳」을 또 적어, 일수가 두 번 나오고 곳수는 제목의
    /// 「외 6곳」(교통시설 뺀 수)과 어긋났다. 곳수는 제목이 이미 말하니 세지 않는다.
    ///
    /// 뒤로가기 버튼(36)이 왼쪽 위에 떠 있으니 그 줄을 비워 두고 아래에서 시작한다.
    private var header: some View {
        VStack(spacing: PixelSpacing.m) {
            Text(course.title.isEmpty ? "이름 없는 코스" : course.placeHeadline)
                .font(PixelFont.sectionTitle)
                .foregroundColor(PixelColor.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: PixelSpacing.s) {
                let region = course.regionOrAll
                let c = JejuRegionDef.colors(for: region)
                headerChip(fill: c.fill, on: c.on) {
                    Text(region)
                }
                headerChip(fill: PixelColor.surface, on: PixelColor.ink) {
                    HStack(spacing: PixelSpacing.xs) {
                        PixelIcon(.calendar, size: 14)
                        Text("\(course.durationDays)일 일정")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PixelSpacing.xxxl + PixelSpacing.s)
        .padding(.top, PixelSpacing.s + 36 + PixelSpacing.m)
        .padding(.bottom, PixelSpacing.l)
    }

    /// 제목 아래 칩. 픽셀 버튼과 같은 꼴(테두리 2 + 작은 그림자)로, 목록 카드의
    /// 배지와 같은 높이(28)다.
    private func headerChip<Content: View>(fill: Color, on: Color,
                                           @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(PixelFont.labelSmall)
            .foregroundColor(on)
            .padding(.horizontal, PixelSpacing.s + 2)
            .frame(height: 28)
            .background(fill)
            .pixelBorder(width: PixelSpacing.border)
            .pixelShadow(PixelSpacing.shadowSmall)
    }

    // MARK: - Map

    /// 지도 영역의 높이. 화면 폭에 관계없이 고정한다 — 아래 목록이 첫 화면에
    /// 한두 장은 보여야 「지도 아래에 일정이 있다」는 것을 알 수 있다.
    private let mapHeight: CGFloat = 280

    private var courseMap: some View {
        // ⚠️ 번호는 **코스 전체 기준**이다 (2026-09-09). 고른 날만 다시 1부터
        // 세면, Day 2 를 골랐을 때 지도 마커는 1·2·3·4 인데 아래 목록은 5·6·7·8 이라
        // 같은 장소에 번호가 두 개 붙는다.
        let markers = indexedPlaces.filter { $0.place.day == selectedDay }
        let coords = markers.map {
            CLLocationCoordinate2D(latitude: $0.place.lat, longitude: $0.place.lng)
        }
        // Day 를 바꾸면 그날 장소가 모두 들어오도록 카메라를 다시 맞춘다.
        // 한 동네에 몰린 날은 확대되고, 동서로 퍼진 날은 축소된다 — 날마다 배율이 다르다.
        return MapWithPolyline(coordinates: coords, annotationItems: markers)
            .frame(height: mapHeight)
            .clipped()
    }

    // MARK: - Day Tab Bar

    private var dayTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // 「전체」는 없앴다. 다시 누르면 해제되던 것도 없앴다 — 해제되면 결국
            // 「전체」와 같은 상태로 돌아가, 없앤 것이 뒷문으로 다시 들어온다.
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    DayTabButton(title: "Day \(day)", isSelected: selectedDay == day) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedDay = day }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Action Buttons

    private var regionColors: (fill: Color, on: Color) {
        JejuRegionDef.colors(for: course.regionOrAll)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 이 물음은 「담기」에게 하는 말이다. 이미 담아 둔 코스로 들어왔을 때는
            // 담기와 함께 사라진다 — 남겨두면 답할 데 없는 질문만 떠 있다.
            if showsSaveButton {
                Text("추천 일정이 마음에 드세요?")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.inkWeak)
            }

            // 「다시하기」·「새로운 추천」은 걷어냈다 (2026-09-09 조익준님 결정).
            // 둘 다 뒤로 가서 목록에서 다른 코스를 고르는 것과 결과가 같았다 —
            // 같은 일을 하는 문이 세 개면 어느 문이 무엇인지 오히려 흐려진다.
            if showsSaveButton {
                Button {
                    vm.save(context: modelContext)
                } label: {
                    Label {
                        Text(vm.isSaved ? "저장됨" : "담기")
                    } icon: {
                        PixelIcon(vm.isSaved ? .check : .download, size: 16)
                    }
                        .font(PixelFont.label)
                        .frame(maxWidth: .infinity)
                }
                // 담기는 위 권역 칩과 같은 색 — 화면이 초록 한 가지로 몰리지 않게
                // (2026-09-10 조익준님 결정). 「전체」 코스는 칩처럼 잉크.
                .buttonStyle(PixelButtonStyle(.tinted(fill: regionColors.fill, label: regionColors.on)))
                .disabled(vm.isSaved)
            }

            if onRename != nil || onDelete != nil {
                HStack(spacing: 10) {
                    if let onRename {
                        Button(action: onRename) {
                            Label { Text("이름 변경") } icon: { PixelIcon(.edit, size: 16) }
                                .font(PixelFont.labelSmall)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PixelButtonStyle(.plain))
                    }
                    if let onDelete {
                        // 삭제는 되돌릴 수 없다. 글자만 경고색으로 두고 면은 흰색으로
                        // 남긴다 — 빨간 덩어리를 옆에 두면 누르라는 말처럼 보인다.
                        Button(action: onDelete) {
                            Label { Text("삭제") } icon: { PixelIcon(.close, size: 16) }
                                .font(PixelFont.labelSmall)
                                .foregroundColor(PixelColor.locked)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PixelButtonStyle(.plain))
                    }
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        // 탭바를 숨겼으니 홈 인디케이터 자리까지 이 바가 채운다.
        .background(PixelColor.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            PixelColor.ink.frame(height: PixelSpacing.borderHeavy)
        }
    }

    // MARK: - Toast

    /// 실패는 **다른 색**으로 띄운다. 같은 초록으로 띄우면 「담지 못했어요」가
    /// 성공 알림처럼 스쳐 지나간다.
    private func toastView(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(PixelFont.body)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(isError ? PixelColor.locked : PixelColor.done)
            .foregroundColor(isError ? PixelColor.onLocked : PixelColor.onDone)
            .clipShape(Rectangle())
            .padding(.top, PixelSpacing.s + 36 + PixelSpacing.s)
    }

    // MARK: - Helpers

    /// day 섹션의 첫 번째 장소가 전체 places 배열에서 갖는 오프셋 (마커 번호용)
    private func globalOffset(for day: Int) -> Int {
        guard let firstPlace = placesByDay[day]?.first else { return 0 }
        let idx = course.places.firstIndex { p in
            p.name == firstPlace.name && p.day == firstPlace.day
        }
        return idx ?? 0
    }
}

// MARK: - DaySectionView

private struct DaySectionView: View {
    let day: Int
    let places: [CoursePlace]
    let globalOffset: Int   // 전체 배열에서의 시작 번호 오프셋
    let onPlaceTap: (CoursePlace) -> Void

    var body: some View {
        // ⚠️ 섹션 머리(「Day 1 ────」)를 뺐다 (2026-09-09). 목록이 고른 하루만
        // 보여주게 되면서, 바로 위 칩이 이미 하고 있는 말을 한 번 더 하는 자리가 됐다.
        VStack(alignment: .leading, spacing: 0) {
            // 카드를 누르면 장소 정보가 열린다는 것을 **말로도** 알린다 (2026-09-10
            // 조익준님 결정). 테두리·그림자·화살표만으로는 눌리는 줄 모를 수 있다.
            HStack(spacing: PixelSpacing.xs) {
                PixelIcon(.info, size: 14, color: PixelColor.inkWeak)
                Text("장소를 누르면 이용 정보를 볼 수 있어요")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.inkWeak)
            }
            .padding(.horizontal, PixelSpacing.xl)
            .padding(.bottom, PixelSpacing.m)

            // 장소 카드 목록 — 장소 상세의 카드와 같은 테두리·그림자. 누르면
            // 그림자 속으로 가라앉는다.
            ForEach(Array(places.enumerated()), id: \.offset) { idx, place in
                Button { onPlaceTap(place) } label: {
                    PlaceCard(index: globalOffset + idx + 1, place: place)
                }
                .buttonStyle(PixelPressStyle(offset: PixelSpacing.shadowSmall))
                .padding(.horizontal, PixelSpacing.xl)
                .padding(.bottom, PixelSpacing.m)
            }
        }
    }
}

// MARK: - DayTabButton

private struct DayTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PixelFont.labelSmall)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? PixelColor.primary : PixelColor.primary.opacity(0.1))
                .foregroundColor(isSelected ? PixelColor.onPrimary : PixelColor.primary)
                .clipShape(Rectangle())
        }
    }
}

// MARK: - MapWithPolyline (MKMapView + polyline + 번호 마커)

private struct MapWithPolyline: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let annotationItems: [IndexedPlace]

    func makeUIView(context: Context) -> RouteMapView {
        let mapView = RouteMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        return mapView
    }

    func updateUIView(_ mapView: RouteMapView, context: Context) {
        // ⚠️ **경로가 그대로면 아무것도 건드리지 않는다** (2026-09-10 조익준님 지적).
        //
        // 이 함수는 화면이 다시 그려질 때마다 불린다. 그때마다 마커를 지웠다 다시
        // 만들면 새 뷰가 제자리를 찾기까지 한 박자가 뜨고, 카메라까지 다시 맞추면
        // 사용자가 손으로 옮겨 둔 지도가 튕겨 돌아온다. Day 가 바뀌었을 때만 한다.
        let key = annotationItems.map { "\($0.index):\($0.place.lat),\($0.place.lng)" }
            .joined(separator: "|")
        guard context.coordinator.routeKey != key else { return }
        context.coordinator.routeKey = key

        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        for item in annotationItems {
            mapView.addAnnotation(NumberedAnnotation(
                index: item.index,
                coordinate: CLLocationCoordinate2D(latitude: item.place.lat,
                                                   longitude: item.place.lng)
            ))
        }
        if coordinates.count >= 2 {
            mapView.addOverlay(MKPolyline(coordinates: coordinates,
                                          count: coordinates.count),
                               level: .aboveRoads)
        }

        // 그날 장소가 모두 들어오는 사각형. 날마다 넓이가 달라 배율도 달라진다.
        //
        // ⚠️ 갈래를 **하나로** 둔다. 한때 「점이 하나일 때」만 따로 `setRegion` 을
        // 썼는데, 그 갈래가 `edgePadding` 을 안 타서 마커가 가장자리에 걸렸다.
        // 좁으면 넓히고, 맞추는 방법은 하나로 한다.
        var rect = mapView.annotations.reduce(MKMapRect.null) { acc, ann in
            let point = MKMapPoint(ann.coordinate)
            return acc.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        if !rect.isNull {
            // 점 하나거나 거의 한 줄이면 넓이가 0에 가까워 최대 배율로 붙는다.
            // 그 자리에서 반경 800m 를 확보한다.
            let center = MKMapPoint(x: rect.midX, y: rect.midY)
            let minSide = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude) * 800
            if rect.size.width < minSide || rect.size.height < minSide {
                let w = max(rect.size.width, minSide)
                let h = max(rect.size.height, minSide)
                rect = MKMapRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            }
        }
        mapView.fit(to: rect.isNull ? nil : rect)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        /// 지금 지도에 올라가 있는 경로의 지문. 이게 그대로면 마커를 다시 만들지 않는다.
        var routeKey: String = ""

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = PixelUIColor.primary.withAlphaComponent(0.85)
                renderer.lineWidth = 3.5
                renderer.lineDashPattern = [8, 5]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let numbered = annotation as? NumberedAnnotation else { return nil }
            let id = "numbered"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.subviews.forEach { $0.removeFromSuperview() }
            view.canShowCallout = false

            // ⚠️ `view.frame` 을 건드리지 않는다 (2026-09-10 조익준님 지적).
            //
            // 마커의 자리는 **MapKit 이 정한다** — 좌표를 화면으로 옮긴 뒤 이 뷰의
            // `center` 를 거기에 놓는다. 그런데 `frame` 을 통째로 넣으면 **위치까지**
            // 함께 덮어써서(원점 0,0) 지도 왼쪽 위로 튀고, MapKit 이 다음 배치에서
            // 다시 제자리로 돌려놓기 전까지 어긋난 채로 보인다.
            //
            // 그 「다음 배치」가 언제 오느냐가 시트에 달려 있었다. 시트를 올리거나
            // 내리면 화면을 다시 맞추면서 배치가 한 번 더 돌아 제자리를 찾고, 안
            // 건드리면 어긋난 채로 남는다 — 번호만 경로에서 떨어져 보이던 이유다.
            //
            // 크기는 `bounds` 로 준다. `bounds` 는 위치를 건드리지 않는다.
            let marker = UIHostingController(
                rootView: NumberedMarker(number: numbered.index + 1)
            )
            marker.view.backgroundColor = .clear
            view.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
            view.centerOffset = .zero      // 번호 한가운데가 그 좌표다
            marker.view.frame = view.bounds
            marker.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(marker.view)
            return view
        }
    }
}

// MARK: - RouteMapView

/// 「이 사각형이 다 보이게」를 기억해 두는 지도.
///
/// SwiftUI 가 `updateUIView` 를 부르는 순간 지도는 아직 크기가 0 일 수 있다.
/// 그때 `setVisibleMapRect` 를 하면 0×0 에 맞춘 셈이라 엉뚱한 배율이 된다.
/// 그래서 맞출 사각형을 들고 있다가, **크기가 정해지거나 바뀔 때** 다시 맞춘다.
/// 전에는 시트가 움직일 때마다 갱신이 한 번 더 돌아서 우연히 맞았다.
private final class RouteMapView: MKMapView {
    private var fitRect: MKMapRect?
    private var fittedBounds: CGRect = .zero

    func fit(to rect: MKMapRect?) {
        fitRect = rect
        fittedBounds = .zero
        applyFitIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFitIfNeeded()
    }

    private func applyFitIfNeeded() {
        guard bounds.width > 0, bounds.height > 0, bounds != fittedBounds else { return }
        fittedBounds = bounds
        if let rect = fitRect {
            setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 32, left: 40, bottom: 32, right: 40),
                animated: false
            )
        } else {
            // 장소 좌표가 하나도 없으면 제주 전체.
            setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 33.38, longitude: 126.55),
                span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.8)
            ), animated: false)
        }
    }
}

// MARK: - NumberedAnnotation

private final class NumberedAnnotation: NSObject, MKAnnotation {
    let index: Int
    let coordinate: CLLocationCoordinate2D

    init(index: Int, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.coordinate = coordinate
    }
}

// MARK: - Helpers

struct IndexedPlace: Identifiable {
    let id: Int
    let index: Int
    let place: CoursePlace
    init(index: Int, place: CoursePlace) {
        self.id = index
        self.index = index
        self.place = place
    }
}

struct NumberedMarker: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(PixelFont.labelSmall)
            .foregroundColor(PixelColor.onPrimary)
            .frame(width: 28, height: 28)
            .background(PixelColor.primary)
            .pixelBorder()
    }
}

// MARK: - PlaceCard

struct PlaceCard: View {
    let index: Int
    let place: CoursePlace

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NumberedMarker(number: index)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.ink)
                    .multilineTextAlignment(.leading)
                if let time = place.startTime, !time.isEmpty {
                    Text(time)
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                }
            }

            Spacer(minLength: 0)

            // 「눌러서 들어가는 줄」이라는 표시. 장소 상세의 주변 시설 줄과 같다.
            PixelIcon(.forward, size: 18, color: PixelColor.inkWeak)
                .padding(.top, 7)
        }
        .padding(PixelSpacing.m)
        .background(PixelColor.surface)
        .pixelBorder()
        .contentShape(Rectangle())
    }
}

// MARK: - Preview (API 없이 바로 확인)

#Preview {
    let mockCourse = Course(
        id: "preview-001",
        title: "2박3일 제주 해안 여행",
        durationDays: 3,
        places: [
            CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1),
            CoursePlace(name: "섭지코지", lat: 33.4299, lng: 126.9279, day: 1),
            CoursePlace(name: "우도", lat: 33.5029, lng: 126.9516, day: 2),
            CoursePlace(name: "협재해수욕장", lat: 33.3941, lng: 126.2393, day: 2),
            CoursePlace(name: "한림공원", lat: 33.4069, lng: 126.2448, day: 3),
            CoursePlace(name: "용두암", lat: 33.5160, lng: 126.5059, day: 3),
        ],
        estimatedMinutes: 360,
        sourceCourseId: "preview-001"
    )
    NavigationStack {
        CoursePreviewView(course: mockCourse)
    }
}


