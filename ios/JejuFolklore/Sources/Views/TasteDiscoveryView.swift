import SwiftUI
import UIKit
import MapKit

// MARK: - TasteDiscoveryView

struct TasteDiscoveryView: View {
    @StateObject private var vm = CourseRecommendViewModel()
    @State private var step = 0
    @State private var selectedRegion = ""
    @State private var selectedQ1 = ""
    @State private var selectedQ2 = ""
    @State private var selectedDays = 1
    @State private var navigateToList = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    progressBar

                    Group {
                        switch step {
                        case 0: regionStep
                        case 1: q1Step
                        case 2: q2Step
                        case 3: daysStep
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

                if vm.isLoadingList {
                    LoadingOverlay(step: vm.loadingStep)
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
            .onChange(of: vm.courseList) {
                if !vm.courseList.isEmpty {
                    navigateToList = true
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
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                Text("\(step + 1) / 4")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("제주 여행 코스 만들기")
                    .font(.title3.weight(.bold))
                Text("실제 여행자들의 검증된 경로로 코스를 추천해드릴게요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.12))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * CGFloat(step + 1) / 4)
                    .animation(.spring(response: 0.4), value: step)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Step 1: 지역 선택 (제주도 지도)

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("어느 지역을 여행하고 싶어요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            JejuMapRegionPicker { region in
                selectedRegion = region
                withAnimation { step = 1 }
            }

            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 2: Q1 — 어떤 이야기 결

    private var q1Step: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("어떤 이야기 결이 끌려요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Q1Option.all) { option in
                    Q1CardView(option: option) {
                        selectedQ1 = option.key
                        withAnimation { step = 2 }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 3: Q2 — 어떤 배경

    private var q2Step: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("어떤 배경이 좋아요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            VStack(spacing: 10) {
                ForEach(Q2Option.all) { option in
                    tasteButton(option.label) {
                        selectedQ2 = option.key
                        withAnimation { step = 3 }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 4: 기간 선택

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("며칠이에요?")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 32)

            HStack(spacing: 10) {
                ForEach([(1, "1일"), (2, "2일"), (3, "3일"), (5, "4일+")], id: \.0) { days, label in
                    Button {
                        selectedDays = days
                        Task { await startSearch() }
                    } label: {
                        Text(label)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private func tasteButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func computeCategoryScores() -> [String: Int] {
        // Q1: 서사 축 점수
        let q1Map: [String: [String: Int]] = [
            "mythology":    ["무속신화·신격 전승": 3, "마을 공동체 전승": 1],
            "supernatural": ["초자연 존재담": 3, "생활민담·교훈담": 1],
            "folktale":     ["생활민담·교훈담": 3, "마을 공동체 전승": 1],
            "community":    ["마을 공동체 전승": 3, "무속신화·신격 전승": 1],
        ]
        // Q2: 공간 축 점수
        let q2Map: [String: [String: Int]] = [
            "ocean":    ["해양·어촌 전승": 3, "초자연 존재담": 1],
            "village":  ["마을 공동체 전승": 2, "무속신화·신격 전승": 1],
            "mountain": ["무속신화·신격 전승": 1, "생활민담·교훈담": 1, "초자연 존재담": 1],
            "any":      [:],
        ]

        var scores: [String: Int] = [:]
        for (cat, score) in q1Map[selectedQ1] ?? [:] {
            scores[cat, default: 0] += score
        }
        for (cat, score) in q2Map[selectedQ2] ?? [:] {
            scores[cat, default: 0] += score
        }
        return scores
    }

    // MARK: - Actions

    private func startSearch() async {
        vm.selectedRegion = selectedRegion
        vm.categoryScores = computeCategoryScores()
        vm.durationDays = selectedDays
        await vm.fetchList()
    }

    private func resetToStart() {
        step = 0
        selectedRegion = ""
        selectedQ1 = ""
        selectedQ2 = ""
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)

            // 선택된 지역 표시
            if !highlighted.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(JejuRegionDef.find(highlighted)?.swiftUIColor ?? .orange)
                        .frame(width: 8, height: 8)
                    Text(highlighted == "전체" ? "제주 전역" : "\(highlighted) (\(JejuRegionDef.find(highlighted)?.sublabel ?? ""))")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: highlighted)
            }
        }
    }
}

// MARK: - 지역 데이터

private struct JejuRegionDef {
    let id: String
    let label: String
    let sublabel: String
    let uiColor: UIColor

    var swiftUIColor: Color { Color(uiColor: uiColor) }

    // 백엔드 GPS 필터와 동일한 기준으로 좌표가 어느 지역인지 판별
    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        switch id {
        case "서부": return coord.longitude < 126.40
        case "북부": return coord.latitude >= 33.45
        case "동부": return coord.longitude >= 126.70
        case "남부": return coord.latitude < 33.30
        default:     return false
        }
    }

    // 지역 폴리곤 좌표 (섬 전체 bounding box 내 직사각형 섹터)
    var polygonCoords: [CLLocationCoordinate2D] {
        switch id {
        case "서부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.10),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.10),
            ]
        case "북부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.45, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.45, longitude: 126.40),
            ]
        case "동부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.97),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.97),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.70),
            ]
        case "남부":
            return [
                CLLocationCoordinate2D(latitude: 33.30, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.30, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.40),
            ]
        default:
            return []
        }
    }

    // 레이블 표시 위치
    var labelCoord: CLLocationCoordinate2D {
        switch id {
        case "서부": return CLLocationCoordinate2D(latitude: 33.38, longitude: 126.24)
        case "북부": return CLLocationCoordinate2D(latitude: 33.51, longitude: 126.52)
        case "동부": return CLLocationCoordinate2D(latitude: 33.38, longitude: 126.83)
        case "남부": return CLLocationCoordinate2D(latitude: 33.22, longitude: 126.55)
        default:     return CLLocationCoordinate2D(latitude: 33.36, longitude: 126.53)
        }
    }

    static let all: [JejuRegionDef] = [
        JejuRegionDef(id: "서부", label: "서부", sublabel: "한림·애월",  uiColor: .systemGreen),
        JejuRegionDef(id: "북부", label: "북부", sublabel: "제주시",     uiColor: .systemBlue),
        JejuRegionDef(id: "동부", label: "동부", sublabel: "성산·구좌",  uiColor: .systemPurple),
        JejuRegionDef(id: "남부", label: "남부", sublabel: "서귀포",     uiColor: .systemRed),
    ]

    static func find(_ id: String) -> JejuRegionDef? {
        all.first { $0.id == id }
    }
}

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
            let color = isAll ? UIColor.systemOrange : (JejuRegionDef.find(region.regionId)?.uiColor ?? .gray)

            if isAll {
                // 전체 버튼: 캡슐 형태
                let container = UIView()
                container.backgroundColor = region.isHighlighted
                    ? UIColor.systemOrange
                    : UIColor.systemOrange.withAlphaComponent(0.15)
                container.layer.cornerRadius = 12
                container.layer.borderWidth = 1.2
                container.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.6).cgColor

                let lbl = UILabel()
                lbl.text = "전체"
                lbl.font = .systemFont(ofSize: 12, weight: .bold)
                lbl.textColor = region.isHighlighted ? .white : .systemOrange
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
                bottom.textColor = region.isHighlighted ? color : UIColor.darkGray.withAlphaComponent(0.7)
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

// MARK: - Q1/Q2 선택지

private struct Q1Option: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let imageName: String

    static let all: [Q1Option] = [
        Q1Option(key: "mythology",    label: "신이 마을에 내려오는 이야기", imageName: "mood_grand_sacred"),
        Q1Option(key: "supernatural", label: "으스스하고 기이한 이야기",     imageName: "mood_mysterious"),
        Q1Option(key: "folktale",     label: "재치 있고 교훈적인 이야기",   imageName: "mood_cheerful"),
        Q1Option(key: "community",    label: "마을 사람들이 함께 전해온 이야기", imageName: "mood_village"),
    ]
}

// MARK: - Q1CardView

private struct Q1CardView: View {
    let option: Q1Option
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                Image(option.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(option.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct Q2Option: Identifiable {
    let id = UUID()
    let key: String
    let label: String

    static let all: [Q2Option] = [
        Q2Option(key: "ocean",    label: "바다와 어촌"),
        Q2Option(key: "village",  label: "마을과 당"),
        Q2Option(key: "mountain", label: "산·오름"),
        Q2Option(key: "any",      label: "상관없어요"),
    ]
}
