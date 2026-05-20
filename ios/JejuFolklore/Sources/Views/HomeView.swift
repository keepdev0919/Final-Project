import SwiftUI
import MapKit

// MARK: - PinGroup (같은 좌표 핀 묶음)

struct PinGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let pins: [Pin]

    var isMultiple: Bool { pins.count > 1 }
    var representativePin: Pin { pins[0] }

    init(pins: [Pin]) {
        self.pins = pins
        self.coordinate = CLLocationCoordinate2D(latitude: pins[0].lat, longitude: pins[0].lng)
        self.id = "\(pins[0].lat)-\(pins[0].lng)"
    }
}

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var selectedGroup: PinGroup?
    @State private var selectedPin: Pin?
    @State private var presentedTodayPin: Pin?
    @State private var presentedCourse: Course?

    /// 지도 줌인용 외부 region (Today 카드 탭 시 갱신)
    @State private var mapTargetRegion: MKCoordinateRegion?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1) 오늘의 설화 카드
                if let today = vm.todayFolklore {
                    TodayFolkloreCard(
                        folklore: today,
                        onTapCard: { focusMap(on: today) },
                        onTapStory: { openTodayStory(today) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 2) 지도 (고정 높이)
                mapSection
                    .padding(.horizontal, 16)

                // 3) 추천 코스
                if !vm.recommendedCourses.isEmpty {
                    recommendedCoursesSection
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }

                if vm.isLoading || vm.isLoadingHomeData {
                    ProgressView("불러오는 중...")
                        .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(.spring(response: 0.35), value: vm.todayFolklore?.codeNo)
        .animation(.easeInOut, value: vm.recommendedCourses.count)
        .task {
            async let pinsTask: () = vm.loadAllPins()
            async let homeTask: () = vm.loadHomeData()
            _ = await (pinsTask, homeTask)
        }
        // 단일 핀 → 팝업 카드
        .sheet(item: $selectedPin) { pin in
            FolkloreDetailView(pin: pin)
                .presentationDetents([.medium, .large])
        }
        // 오늘의 설화 → 상세 시트
        .sheet(item: $presentedTodayPin) { pin in
            FolkloreDetailView(pin: pin)
                .presentationDetents([.medium, .large])
        }
        // 추천 코스 → CoursePreview
        .sheet(item: $presentedCourse) { course in
            NavigationStack {
                CoursePreviewView(course: course, hasNext: false, categoryScores: [:])
            }
        }
        // 복수 핀 → 설화 목록 시트
        .sheet(item: $selectedGroup) { group in
            if group.isMultiple {
                PinListSheet(group: group) { pin in
                    selectedGroup = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedPin = pin
                    }
                }
                .presentationDetents([.medium, .large])
            } else {
                FolkloreDetailView(pin: group.representativePin)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Map section

    private var mapSection: some View {
        // 홈 지도는 Apple Maps 고정 (클러스터링이 Apple Maps 기반으로만 구현됨).
        // 토글 버튼도 노출하지 않는다.
        FolkloreMapView(
            groups: vm.pinGroups,
            targetRegion: mapTargetRegion,
            onSelectGroup: { group in
                selectedGroup = group
            }
        )
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Recommended courses

    private var recommendedCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("당신을 위한 코스 추천")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(vm.recommendedCourses.count)개")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.recommendedCourses) { course in
                        HomeRecommendedCourseCard(
                            course: course,
                            previewImage: nil,
                            onTap: { presentedCourse = course }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Actions

    private func focusMap(on today: TodayFolklore) {
        mapTargetRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: today.lat, longitude: today.lng),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    private func openTodayStory(_ today: TodayFolklore) {
        // 전체 pin 목록에 같은 codeNo 가 있으면 그걸 우선 사용 (전체 정보 보존).
        // 없으면 TodayFolklore 정보로 임시 Pin 합성하여 진입.
        if let matched = vm.pin(for: today) {
            presentedTodayPin = matched
        } else {
            presentedTodayPin = Pin(
                codeNo: today.codeNo,
                title: today.title,
                sourceType: "legend",
                summary: today.hook,
                lat: today.lat,
                lng: today.lng,
                primaryPlace: today.primaryPlace,
                distanceM: nil
            )
        }
    }
}

// MARK: - PinListSheet (복수 설화 목록)

struct PinListSheet: View {
    let group: PinGroup
    let onSelect: (Pin) -> Void

    var body: some View {
        NavigationStack {
            List(group.pins) { pin in
                Button {
                    onSelect(pin)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                            .foregroundColor(pin.sourceType == "legend" ? .orange : .purple)
                            .frame(width: 32, height: 32)
                            .background(
                                (pin.sourceType == "legend" ? Color.orange : Color.purple).opacity(0.12)
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pin.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Text(pin.sourceTypeLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(group.representativePin.primaryPlace) 설화 \(group.pins.count)개")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - GroupAnnotation

final class GroupAnnotation: NSObject, MKAnnotation {
    let group: PinGroup
    var coordinate: CLLocationCoordinate2D { group.coordinate }
    var title: String? {
        group.isMultiple ? "\(group.pins.count)개 설화" : group.representativePin.title
    }

    init(group: PinGroup) { self.group = group }
}

// MARK: - FolkloreMapView

struct FolkloreMapView: UIViewRepresentable {
    let groups: [PinGroup]
    /// 외부에서 지도 영역을 강제 이동시키고 싶을 때 사용.
    /// 같은 region 이 연속으로 들어와도 set 되도록 Coordinator 가 lastApplied 를 기억한다.
    var targetRegion: MKCoordinateRegion? = nil
    let onSelectGroup: (PinGroup) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        mapView.setRegion(region, animated: false)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "group")
        LocationService.shared.requestWhenInUseAuthorization()
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // annotations
        let existing = mapView.annotations.compactMap { $0 as? GroupAnnotation }
        if existing.count != groups.count {
            mapView.removeAnnotations(existing)
            mapView.addAnnotations(groups.map { GroupAnnotation(group: $0) })
        }

        // 외부 region 명령 적용
        if let target = targetRegion,
           !context.coordinator.regionEquals(target, context.coordinator.lastAppliedRegion) {
            mapView.setRegion(target, animated: true)
            context.coordinator.lastAppliedRegion = target
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FolkloreMapView
        var lastAppliedRegion: MKCoordinateRegion?

        init(_ parent: FolkloreMapView) { self.parent = parent }

        func regionEquals(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion?) -> Bool {
            guard let b = b else { return false }
            return abs(a.center.latitude - b.center.latitude) < 0.00001 &&
                   abs(a.center.longitude - b.center.longitude) < 0.00001 &&
                   abs(a.span.latitudeDelta - b.span.latitudeDelta) < 0.00001 &&
                   abs(a.span.longitudeDelta - b.span.longitudeDelta) < 0.00001
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let groupAnnotation = annotation as? GroupAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: "group", for: groupAnnotation
            ) as? MKMarkerAnnotationView

            let group = groupAnnotation.group
            if group.isMultiple {
                view?.markerTintColor = .systemOrange
                view?.glyphText = "\(group.pins.count)"
                view?.titleVisibility = .hidden
            } else {
                let pin = group.representativePin
                view?.markerTintColor = pin.sourceType == "legend" ? .systemOrange : .systemPurple
                view?.glyphImage = UIImage(systemName: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                view?.titleVisibility = .hidden
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let groupAnnotation = view.annotation as? GroupAnnotation else { return }
            mapView.deselectAnnotation(groupAnnotation, animated: false)
            parent.onSelectGroup(groupAnnotation.group)
        }
    }
}
