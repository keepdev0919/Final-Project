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
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToExplore) {
            ExploreView(course: course, transport: "car")
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
        let mapView = MapWithPolyline(
            coordinates: coords,
            annotationItems: markers,
            onCollapse: {
                withAnimation(.spring(response: 0.35)) {
                    isSheetExpanded = false
                }
            }
        )
        return AnyView(
            mapView.ignoresSafeArea(edges: Edge.Set.top)
        )
    }

    // MARK: - Bottom Sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // 드래그 핸들 — 탭하면 펼침/접힘 토글
            Button {
                withAnimation(.spring(response: 0.35)) {
                    isSheetExpanded.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 4)
                    if !isSheetExpanded {
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, isSheetExpanded ? 0 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSheetExpanded {
                // Day 탭 필터
                if days.count > 1 {
                    dayTabBar
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // TODO: 내러티브 생성 시점 재설계 예정 — 코스 확정 시점으로 이동할 것
                        // if !course.narrative.isEmpty {
                        //     NarrativeCard(text: course.narrative)
                        //         .padding(.horizontal, 16)
                        //         .padding(.top, 12)
                        //         .padding(.bottom, 8)
                        // }

                        // Day 섹션별 장소 목록
                        ForEach(days, id: \.self) { day in
                            if selectedDay == nil || selectedDay == day {
                                DaySectionView(
                                    day: day,
                                    places: placesByDay[day] ?? [],
                                    globalOffset: globalOffset(for: day)
                                )
                            }
                        }

                        Spacer(minLength: 8)
                    }
                }
                .frame(maxHeight: 400)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 하단 버튼 (항상 표시)
            actionButtons
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                // 다시하기
                Button {
                    dismiss()
                    onReset?()
                } label: {
                    Label("다시하기", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                // 새로운 추천받기 (다음 코스 없으면 비활성)
                Button {
                    dismiss()
                    onNext?()
                } label: {
                    Label("새로운 추천", systemImage: "shuffle")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!hasNext)

                // 내 일정으로 담기
                Button {
                    vm.save(context: modelContext)
                } label: {
                    Label(vm.isSaved ? "저장됨" : "담기", systemImage: vm.isSaved ? "checkmark" : "square.and.arrow.down")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isSaved)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Toast

    private var toastView: some View {
        Text("코스가 저장됐어요!")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(Capsule())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            HStack {
                Text("Day \(day)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.orange.opacity(0.25))
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
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.orange : Color.orange.opacity(0.1))
                .foregroundColor(isSelected ? .white : .orange)
                .clipShape(Capsule())
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
                coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng),
                hasfolklore: !item.place.folklorePins.isEmpty
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
                rootView: NumberedMarker(number: numbered.index + 1, hasfolklore: numbered.hasfolklore)
            )
            marker.view.backgroundColor = .clear
            marker.view.frame = CGRect(x: 0, y: 0, width: numbered.hasfolklore ? 44 : 32, height: 32)
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
    let hasfolklore: Bool

    init(index: Int, coordinate: CLLocationCoordinate2D, hasfolklore: Bool) {
        self.index = index
        self.coordinate = coordinate
        self.hasfolklore = hasfolklore
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
    var hasfolklore: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.orange)
                .clipShape(Circle())
                .shadow(radius: 3)

            if hasfolklore {
                Text("📖")
                    .font(.system(size: 12))
                    .shadow(radius: 1)
            }
        }
    }
}

struct NarrativeCard: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("여행 이야기")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "접기" : "더 보기")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                }
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
        }
        .padding(14)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - PlaceCard (설화 expand 포함)

struct PlaceCard: View {
    let index: Int
    let place: CoursePlace
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 장소 기본 정보 행
            HStack(alignment: .top, spacing: 12) {
                NumberedMarker(number: index, hasfolklore: false)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                    if let time = place.startTime, !time.isEmpty {
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 설화가 있으면 오른쪽에 뱃지
                if !place.folklorePins.isEmpty {
                    Text("설화 \(place.folklorePins.count)개")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(12)

            // 설화 expand 토글 (설화가 있을 때만)
            if !place.folklorePins.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(isExpanded ? "설화 접기" : "설화 \(place.folklorePins.count)개 보기")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.orange)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(place.folklorePins) { pin in
                            FolklorePinRow(pin: pin)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FolklorePinRow

private struct FolklorePinRow: View {
    let pin: Pin

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(pin.sourceTypeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(Capsule())

                Text(pin.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            if !pin.summary.isEmpty {
                Text(pin.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.04))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 3),
            alignment: .leading
        )
    }
}

// MARK: - Preview (API 없이 바로 확인)

#Preview {
    let mockPin = Pin(
        codeNo: "mock-001",
        title: "설문대할망 전설",
        sourceType: "legend",
        summary: "제주도를 창조한 거인 신 설문대할망의 이야기. 한라산을 베개 삼아 누웠을 만큼 거대했다고 전해진다.",
        lat: 33.499,
        lng: 126.531,
        primaryPlace: "한라산",
        distanceM: 450
    )
    let mockCourse = Course(
        id: "preview-001",
        title: "2박3일 제주 해안 여행",
        durationDays: 3,
        places: [
            CoursePlace(name: "성산일출봉", lat: 33.4584, lng: 126.9426, day: 1, folklorePins: [mockPin]),
            CoursePlace(name: "섭지코지", lat: 33.4299, lng: 126.9279, day: 1, folklorePins: [mockPin, mockPin]),
            CoursePlace(name: "우도", lat: 33.5029, lng: 126.9516, day: 2, folklorePins: []),
            CoursePlace(name: "협재해수욕장", lat: 33.3941, lng: 126.2393, day: 2, folklorePins: [mockPin]),
            CoursePlace(name: "한림공원", lat: 33.4069, lng: 126.2448, day: 3, folklorePins: []),
            CoursePlace(name: "용두암", lat: 33.5160, lng: 126.5059, day: 3, folklorePins: [mockPin]),
        ],
        estimatedMinutes: 360,
        sourceCourseId: "preview-001",
        narrative: "제주의 동쪽 끝, 성산일출봉에서 여행이 시작됩니다. 바다 위로 솟아오른 분화구를 오르며 제주의 탄생 신화를 품은 땅을 밟습니다. 섭지코지의 바람을 맞으며 걷다 보면, 옛 어부들이 바다의 신에게 빌었던 기도 소리가 들리는 듯합니다. 우도의 맑은 바다는 천지왕이 창조했다는 전설처럼 눈이 시릴 만큼 푸릅니다."
    )
    NavigationStack {
        CoursePreviewView(course: mockCourse)
    }
}
