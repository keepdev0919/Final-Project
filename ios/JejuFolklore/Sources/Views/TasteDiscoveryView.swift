import SwiftUI
import MapKit

// MARK: - TasteDiscoveryView

struct TasteDiscoveryView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var step = 0
    @State private var selectedRegion = ""
    @State private var selectedDays = 1
    @State private var navigateToList = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    progressBar
                        .padding(.horizontal, PixelSpacing.screenMargin)
                        .padding(.bottom, PixelSpacing.l)

                    Group {
                        switch step {
                        case 0: regionStep
                        case 1: daysStep
                        default: EmptyView()
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    Spacer()
                }

            }
            .animation(.spring(response: 0.35), value: step)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToList) {
                CourseListView(vm: vm)
                    .onDisappear {
                        if vm.courseList.isEmpty { vm.reset() }
                    }
            }
            .alert("코스를 가져오지 못했어요", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("다시 시도") { Task { await startSearch() } }
                Button("처음으로", role: .cancel) { resetToStart() }
            } message: {
                Text(vm.errorMessage ?? "네트워크를 확인하고 다시 시도해주세요.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation { step -= 1 }
                    } label: {
                        PixelIcon(.back, size: 16)
                            .foregroundColor(PixelColor.ink)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                Text("\(step + 1) / 2")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.inkWeak)

                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("제주 여행 코스 만들기")
                    .font(PixelFont.bodyLarge)
                Text("실제 여행자들의 검증된 경로로 코스를 추천해드릴게요")
                    .font(PixelFont.labelSmall)
                    .foregroundColor(PixelColor.inkWeak)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Progress Bar

    /// 두 단계뿐이므로 "칸으로 나뉜 막대"를 쓴다 — 몇 걸음 남았는지 세어진다.
    private var progressBar: some View {
        PixelProgressBar(total: 2, filled: step + 1)
            .animation(.spring(response: 0.4), value: step)
    }

    // MARK: - Step 1: 지역 선택 (제주도 지도)

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("어느 지역을 여행하고 싶어요?")
                    .font(PixelFont.sectionTitle)
                Text("4개 권역 또는 '전체'에서 골라주세요")
                    .font(PixelFont.body)
                    .foregroundColor(PixelColor.inkWeak)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            JejuMapRegionPicker { region in
                selectedRegion = region
                withAnimation { step = 1 }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 2: 기간 선택

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("며칠이에요?")
                .font(PixelFont.sectionTitle)
                .padding(.horizontal, 24)
                .padding(.top, 32)

            HStack(spacing: 10) {
                ForEach([(1, "1일"), (2, "2일"), (3, "3일"), (5, "4일+")], id: \.0) { days, label in
                    Button {
                        selectedDays = days
                        Task { await startSearch() }
                    } label: {
                        Text(label)
                            .font(PixelFont.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(PixelColor.surfaceLow)
                            .foregroundColor(PixelColor.ink)
                            .clipShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    // MARK: - Actions

    private func startSearch() async {
        vm.selectedRegion = selectedRegion
        vm.durationDays = selectedDays
        navigateToList = true
        await vm.fetchList()
    }

    private func resetToStart() {
        step = 0
        selectedRegion = ""
        selectedDays = 1
        vm.reset()
    }
}

// MARK: - 제주 지도 지역 선택 컴포넌트

private struct JejuMapRegionPicker: View {
    let onSelect: (String) -> Void
    @State private var highlighted: String = "전체"

    var body: some View {
        VStack(spacing: 12) {
            JejuRegionMapView(highlighted: highlighted) { region in
                highlighted = region
                onSelect(region)
            }
            .aspectRatio(1.75, contentMode: .fit)
            .clipShape(Rectangle())
            

            // 선택된 지역 표시
            if !highlighted.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(JejuRegionDef.find(highlighted)?.swiftUIColor ?? PixelColor.primary)
                        .frame(width: 8, height: 8)
                    Text(highlighted == "전체" ? "제주 전역" : "\(highlighted) (\(JejuRegionDef.find(highlighted)?.sublabel ?? ""))")
                        .font(PixelFont.labelSmall)
                        .foregroundColor(PixelColor.ink)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: highlighted)
            }
        }
    }
}

// MARK: - 지역 데이터

// MARK: - MKMapView 기반 지역 선택 뷰

private final class RegionAnnotation: NSObject, MKAnnotation {
    let regionId: String
    let label: String
    let sublabel: String
    let coordinate: CLLocationCoordinate2D
    var isHighlighted: Bool

    init(def: JejuRegionDef, isHighlighted: Bool) {
        self.regionId = def.id
        self.label = def.label
        self.sublabel = def.sublabel
        self.coordinate = def.labelCoord
        self.isHighlighted = isHighlighted
    }

    // 전체 버튼용
    init(coord: CLLocationCoordinate2D, isHighlighted: Bool) {
        self.regionId = "전체"
        self.label = "전체"
        self.sublabel = "제주 전역"
        self.coordinate = coord
        self.isHighlighted = isHighlighted
    }
}

private struct JejuRegionMapView: UIViewRepresentable {
    let highlighted: String
    let onSelect: (String) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsUserLocation = false

        // 제주도 전체가 보이는 고정 뷰포트
        let center = CLLocationCoordinate2D(latitude: 33.355, longitude: 126.53)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.52, longitudeDelta: 0.90)
        )
        mapView.setRegion(region, animated: false)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.highlighted = highlighted

        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // 4개 지역 폴리곤 + 레이블 어노테이션
        for def in JejuRegionDef.all {
            var coords = def.polygonCoords
            let poly = MKPolygon(coordinates: &coords, count: coords.count)
            poly.title = def.id
            mapView.addOverlay(poly, level: .aboveRoads)
            mapView.addAnnotation(RegionAnnotation(def: def, isHighlighted: highlighted == def.id))
        }

        // 전체 선택 버튼 (중앙)
        let allCoord = CLLocationCoordinate2D(latitude: 33.365, longitude: 126.53)
        mapView.addAnnotation(RegionAnnotation(coord: allCoord, isHighlighted: highlighted == "전체"))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, highlighted: highlighted)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (String) -> Void
        var highlighted: String

        init(onSelect: @escaping (String) -> Void, highlighted: String) {
            self.onSelect = onSelect
            self.highlighted = highlighted
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            // 탭된 지역 판별 (백엔드 GPS 필터와 동일 기준)
            for def in JejuRegionDef.all {
                if def.contains(coord) {
                    onSelect(def.id)
                    return
                }
            }
            // 어느 지역에도 속하지 않으면 전체
            onSelect("전체")
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let regionId = polygon.title,
                  let def = JejuRegionDef.find(regionId) else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolygonRenderer(polygon: polygon)
            let isSelected = highlighted == regionId
            renderer.fillColor = def.uiColor.withAlphaComponent(isSelected ? 0.40 : 0.12)
            renderer.strokeColor = def.uiColor.withAlphaComponent(isSelected ? 0.85 : 0.35)
            renderer.lineWidth = isSelected ? 2.5 : 1.0
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let region = annotation as? RegionAnnotation else { return nil }

            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: "region-\(region.regionId)")
            view.canShowCallout = false

            let label = UILabel()
            label.numberOfLines = 2
            label.textAlignment = .center

            let isAll = region.regionId == "전체"
            let color = isAll ? PixelUIColor.primary : (JejuRegionDef.find(region.regionId)?.uiColor ?? PixelUIColor.inkWeak)

            if isAll {
                // 전체 버튼: 캡슐 형태
                let container = UIView()
                container.backgroundColor = region.isHighlighted
                    ? PixelUIColor.primary
                    : PixelUIColor.surface
                container.layer.cornerRadius = 0  // 각진 모서리
                container.layer.borderWidth = 2   // 테두리 2px
                container.layer.borderColor = PixelUIColor.ink.cgColor

                let lbl = UILabel()
                lbl.text = "전체"
                lbl.font = .systemFont(ofSize: 12, weight: .bold)
                lbl.textColor = region.isHighlighted ? PixelUIColor.onPrimary : PixelUIColor.ink
                lbl.sizeToFit()

                let w = lbl.frame.width + 20
                let h: CGFloat = 28
                container.frame = CGRect(x: 0, y: 0, width: w, height: h)
                lbl.center = CGPoint(x: w / 2, y: h / 2)
                container.addSubview(lbl)
                view.addSubview(container)
                view.frame = container.frame
                view.centerOffset = CGPoint(x: 0, y: 0)
            } else {
                // 지역 레이블
                let top = UILabel()
                top.text = region.label
                top.font = .systemFont(ofSize: 12, weight: .bold)
                top.textColor = region.isHighlighted ? color : color.withAlphaComponent(0.85)
                top.sizeToFit()

                let bottom = UILabel()
                bottom.text = region.sublabel
                bottom.font = .systemFont(ofSize: 10, weight: .regular)
                bottom.textColor = region.isHighlighted ? color : PixelUIColor.inkWeak
                bottom.sizeToFit()

                let w = max(top.frame.width, bottom.frame.width) + 4
                let h = top.frame.height + bottom.frame.height + 2
                top.frame.origin = CGPoint(x: (w - top.frame.width) / 2, y: 0)
                bottom.frame.origin = CGPoint(x: (w - bottom.frame.width) / 2, y: top.frame.height + 2)

                let container = UIView(frame: CGRect(x: 0, y: 0, width: w, height: h))
                container.addSubview(top)
                container.addSubview(bottom)
                view.addSubview(container)
                view.frame = container.frame
            }
            return view
        }
    }
}

