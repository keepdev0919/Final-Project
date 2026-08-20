import SwiftUI
import MapKit
import SwiftData

// MARK: - CoursePreviewView

struct CoursePreviewView: View {
    let course: Course
    let hasNext: Bool
    let onNext: (() -> Void)?
    let onReset: (() -> Void)?
    @StateObject private var vm: CoursePreviewViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToExplore = false
    @State private var selectedDay: Int? = nil
    @State private var isSheetExpanded = true
    @State private var selectedPlace: CoursePlace?

    init(course: Course, hasNext: Bool = false, onNext: (() -> Void)? = nil, onReset: (() -> Void)? = nil) {
        self.course = course
        self.hasNext = hasNext
        self.onNext = onNext
        self.onReset = onReset
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
            if vm.showSavedToast {
                toastView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: vm.showSavedToast)
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToExplore) {
            ExploreView(
                course: course,
                transport: "car"
            )
        }
        // 탐험 완료 시 자신도 dismiss → TabView root까지 연쇄적으로 pop.
        // ExploreView가 4단 push(TasteDiscovery → CourseList → CoursePreview → Explore)
        // 안에 있을 수 있어, dismiss 한 번으로는 root에 도달 못 함.
        .onReceive(NotificationCenter.default.publisher(for: .exploreDidComplete)) { _ in
            navigateToExplore = false
            dismiss()
        }
    }

    // MARK: - Map

    private var courseMap: some View {
        let placesToShow = selectedDay == nil
            ? course.places
            : course.places.filter { $0.day == selectedDay }
        let coords = placesToShow.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
        let markers = placesToShow.enumerated().map {
            IndexedPlace(index: $0.offset, place: $0.element)
        }
        let onCollapse = {
            withAnimation(.spring(response: 0.35)) {
                isSheetExpanded = false
            }
        }

        return MapWithPolyline(
            coordinates: coords,
            annotationItems: markers,
            onCollapse: onCollapse
        )
        .ignoresSafeArea(edges: .top)
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

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Day 섹션별 장소 목록
                        ForEach(days, id: \.self) { day in
                            if selectedDay == nil || selectedDay == day {
                                DaySectionView(
                                    day: day,
                                    places: placesByDay[day] ?? [],
                                    globalOffset: globalOffset(for: day),
                                    onPlaceTap: { selectedPlace = $0 }
                                )
                            }
                        }

                        Spacer(minLength: 8)
                    }
                }
                .frame(maxHeight: 260)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 하단 버튼 (항상 표시)
            actionButtons
        }
        .background(PixelColor.surface)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Day Tab Bar

    private var dayTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DayTabButton(title: "전체", isSelected: selectedDay == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDay = nil }
                }
                ForEach(days, id: \.self) { day in
                    DayTabButton(title: "Day \(day)", isSelected: selectedDay == day) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = (selectedDay == day) ? nil : day
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Text("추천 일정이 마음에 드세요?")
                .font(PixelFont.labelSmall)
                .foregroundColor(PixelColor.inkWeak)

            HStack(spacing: 10) {
                // 다시하기
                Button {
                    dismiss()
                    onReset?()
                } label: {
                    Label { Text("다시하기") } icon: { PixelIcon(.refresh, size: 16) }
                        .font(PixelFont.labelSmall)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(.plain))

                // 새로운 추천받기 (다음 코스 없으면 비활성)
                Button {
                    dismiss()
                    onNext?()
                } label: {
                    Label { Text("새로운 추천") } icon: { PixelIcon(.shuffle, size: 16) }
                        .font(PixelFont.labelSmall)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(.plain))
                .disabled(!hasNext)

                // 내 일정으로 담기
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

            Button {
                navigateToExplore = true
            } label: {
                Label { Text("오늘 탐험 시작") } icon: { PixelIcon(.mapPin, size: 16) }
                    .font(PixelFont.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PixelColor.primary)
                    .foregroundColor(PixelColor.surface)
                    .clipShape(Rectangle())
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Toast

    private var toastView: some View {
        Text("코스가 저장됐어요!")
            .font(PixelFont.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(PixelColor.done)
            .foregroundColor(PixelColor.surface)
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
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            HStack {
                Text("Day \(day)")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.surface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(PixelColor.primary)
                    .clipShape(Rectangle())

                Rectangle()
                    .fill(PixelColor.primary.opacity(0.25))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

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
                .foregroundColor(isSelected ? .white : .orange)
                .clipShape(Rectangle())
        }
    }
}

// MARK: - MapWithPolyline (MKMapView + polyline + 번호 마커)

private struct MapWithPolyline: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let annotationItems: [IndexedPlace]
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
        // 기존 오버레이/어노테이션 제거
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // 어노테이션 추가
        for item in annotationItems {
            let annotation = NumberedAnnotation(
                index: item.index,
                coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng)
            )
            mapView.addAnnotation(annotation)
        }

        // Polyline 추가
        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline, level: .aboveRoads)
        }

        // 영역 맞추기
        if !mapView.annotations.isEmpty {
            mapView.showAnnotations(mapView.annotations, animated: false)
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

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onCollapse?()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.85)
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

            // 번호 원형 마커를 UIHostingController로 렌더링
            let marker = UIHostingController(
                rootView: NumberedMarker(number: numbered.index + 1)
            )
            marker.view.backgroundColor = .clear
            marker.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
            view.addSubview(marker.view)
            view.frame = marker.view.frame
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
            .foregroundColor(PixelColor.surface)
            .frame(width: 28, height: 28)
            .background(PixelColor.primary)
            .clipShape(Rectangle())
            
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
