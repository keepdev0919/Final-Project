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
    /// 지도의 아래 끝과 시트의 윗변이 화면에서 각각 어디인지.
    ///
    /// ⚠️ **시트의 「높이」가 아니라 「윗변 위치」를 잰다** (2026-09-10 조익준님 지적).
    /// 높이만 재면 시트 아래 여백(8)과 홈 인디케이터 자리(34)를 빼먹어 늘 42pt 쯤
    /// 덜 빼고 맞췄다. 지도는 화면 맨 아래까지 깔려 있어서(시트 밑으로 지도가 보인다)
    /// 그 42pt 도 가려지는 자리다. 경계에 걸린 마커가 있는 날에만 잘려 보였다.
    @State private var mapBottomY: CGFloat = 0
    @State private var sheetTopY: CGFloat = 0

    /// 지도에서 시트가 덮은 높이.
    private var coveredBySheet: CGFloat {
        max(0, mapBottomY - sheetTopY)
    }
    @State private var isSheetExpanded = true
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
        ZStack(alignment: .bottom) {
            courseMap
            bottomSheet
            if let text = vm.toastText {
                toastView(text, isError: vm.toastIsError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: vm.toastText)
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        // 상단바를 없애고 그 자리에 뒤로가기 + 제목을 **떠 있는 한 벌**로 얹는다.
        // 지도가 화면 끝까지 차는 화면이라 상단바가 그림 위를 가로로 잘랐다.
        .pixelFloatingBack(topInset: PixelSpacing.s, title: course.title)
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

    // MARK: - Map

    private var courseMap: some View {
        // ⚠️ 번호는 **코스 전체 기준**이다 (2026-09-09). 고른 날만 다시 1부터
        // 세면, Day 2 를 골랐을 때 지도 마커는 1·2·3·4 인데 아래 목록은 5·6·7·8 이라
        // 같은 장소에 번호가 두 개 붙는다. 「전체」가 기본이던 시절에는 전체를 볼 때만
        // 맞았고, 하루가 늘 골라져 있게 되면서 항상 어긋나게 됐다.
        let markers = indexedPlaces.filter { $0.place.day == selectedDay }
        let coords = markers.map {
            CLLocationCoordinate2D(latitude: $0.place.lat, longitude: $0.place.lng)
        }
        let onCollapse = {
            withAnimation(.spring(response: 0.35)) {
                isSheetExpanded = false
            }
        }

        return MapWithPolyline(
            coordinates: coords,
            annotationItems: markers,
            // 경로를 **보이는 자리**에 맞춘다 (2026-09-09 조익준님 결정).
            // 전에는 화면 전체를 기준으로 맞춰서, 시트가 아래 절반을 덮고 있는 동안
            // 경로가 시트 뒤에 숨고 위에는 바다만 남았다.
            bottomInset: coveredBySheet,
            topInset: 56,        // 떠 있는 뒤로가기·제목 줄
            onCollapse: onCollapse
        )
        .ignoresSafeArea(edges: .top)
        // 지도의 아래 끝이 화면에서 어디인지 잰다. 홈 인디케이터 자리까지 깔리므로
        // 「화면 높이」로 갈음하면 그만큼 어긋난다.
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: MapBottomKey.self,
                                       value: geo.frame(in: .global).maxY)
            }
        )
        .onPreferenceChange(MapBottomKey.self) { mapBottomY = $0 }
    }

    // MARK: - Bottom Sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // 드래그 핸들 — 탭 or 아래로 스와이프하면 접힘
            Button {
                withAnimation(.spring(response: 0.35)) {
                    isSheetExpanded.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(PixelColor.inkWeak.opacity(0.35))
                        .frame(width: 36, height: 4)
                    if !isSheetExpanded {
                        PixelIcon(.up, size: 16)
                            .foregroundColor(PixelColor.inkWeak)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, isSheetExpanded ? 0 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.height > 40 {
                            withAnimation(.spring(response: 0.35)) { isSheetExpanded = false }
                        } else if value.translation.height < -40 {
                            withAnimation(.spring(response: 0.35)) { isSheetExpanded = true }
                        }
                    }
            )

            if isSheetExpanded {
                // Day 탭 필터
                if days.count > 1 {
                    dayTabBar
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }

                // 고른 하루만 보여준다. 위 칩이 이미 「Day 1」이라고 말하고 있어서
                // 섹션 머리(「Day 1 ────」)는 같은 말을 두 번 하는 자리가 됐다.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        DaySectionView(
                            day: selectedDay,
                            places: placesByDay[selectedDay] ?? [],
                            globalOffset: globalOffset(for: selectedDay),
                            onPlaceTap: { selectedPlace = $0 }
                        )
                        Spacer(minLength: 8)
                    }
                }
                // ⚠️ 높이를 **고정**한다 (2026-09-09). `maxHeight` 로 두면 그날 장소
                // 수에 따라 시트 높이가 달라지고, 지도 카메라는 그 높이를 기준으로
                // 경로를 맞추므로 Day 를 바꿀 때마다 경로가 어긋났다.
                // 어디서 왔느냐에 따라 결과가 달라지던 것도 이것 때문이다.
                .frame(height: 260)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 하단 버튼 (항상 표시)
            actionButtons
        }
        .background(PixelColor.surface)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        // 시트가 실제로 얼마나 덮는지 재서 지도에 알려준다. 값을 박아 두면
        // 시트를 접거나 기기가 바뀔 때 경로가 다시 숨는다.
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SheetTopKey.self,
                                       value: geo.frame(in: .global).minY)
            }
        )
        .onPreferenceChange(SheetTopKey.self) { sheetTopY = $0 }
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
                .buttonStyle(PixelButtonStyle(.primary))
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
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            // 장소 카드 목록
            ForEach(Array(places.enumerated()), id: \.offset) { idx, place in
                PlaceCard(index: globalOffset + idx + 1, place: place)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onTapGesture { onPlaceTap(place) }
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
    /// 아래에서 이만큼은 시트가 덮고 있다. 카메라가 이 자리를 빼고 경로를 맞춘다.
    var bottomInset: CGFloat = 0
    /// 위에서 이만큼은 떠 있는 뒤로가기·제목 줄이 덮는다.
    var topInset: CGFloat = 0
    var onCollapse: (() -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onCollapse = onCollapse

        // ⚠️ **경로가 그대로면 마커도 그대로 둔다** (2026-09-10 조익준님 지적).
        //
        // 이 함수는 시트를 올리고 내릴 때도 불린다. 그때마다 마커를 지웠다 다시
        // 만들면, 새로 만든 뷰가 제자리를 찾기까지 한 박자가 뜬다. 시트를 만질
        // 때마다 번호가 흔들리던 이유다. 바뀐 게 시트뿐이면 **카메라만** 다시 맞춘다.
        let key = annotationItems.map { "\($0.index):\($0.place.lat),\($0.place.lng)" }
            .joined(separator: "|")
        if context.coordinator.routeKey != key {
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
        }

        // 영역 맞추기 — **보이는 자리에** 맞춘다 (2026-09-09 조익준님 결정).
        //
        // 전에는 `showAnnotations` 하나였다. 그건 지도 뷰 **전체**를 기준으로 맞추는데,
        // 이 화면은 아래 절반을 시트가 덮고 있어서 경로가 시트 뒤로 들어가고 위에는
        // 바다만 남았다. 화면은 멀쩡해 보이고 지도도 잘 도는데, 정작 보여주려던
        // 경로만 안 보였다.
        //
        // ⚠️ 갈래를 **하나로** 둔다. 한때 「점이 하나일 때」만 따로 `setRegion` 을
        // 썼는데, 그 갈래가 `edgePadding` 을 안 타서 장소가 하루에 한 곳뿐인 날은
        // 마커가 시트 뒤 한가운데에 숨었다. 좁으면 넓히고, 맞추는 방법은 하나로 한다.
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
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: topInset + 24, left: 40,
                                          bottom: bottomInset + 24, right: 40),
                animated: false
            )
        } else if let first = coordinates.first {
            let region = MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
            )
            mapView.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onCollapse: (() -> Void)?
        /// 지금 지도에 올라가 있는 경로의 지문. 이게 그대로면 마커를 다시 만들지 않는다.
        var routeKey: String = ""

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onCollapse?()
        }

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
                if let time = place.startTime, !time.isEmpty {
                    Text(time)
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.inkWeak)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(PixelColor.surfaceLow)
        .clipShape(Rectangle())
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


/// 시트 **윗변**의 화면 위치. 지도 카메라가 여기부터 아래를 가려진 자리로 친다.
private struct SheetTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 지도 **아래 끝**의 화면 위치. 지도가 홈 인디케이터 자리까지 깔리므로
/// 화면 높이로 갈음하지 않고 직접 잰다.
private struct MapBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
