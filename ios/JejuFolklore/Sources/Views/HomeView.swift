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

    var body: some View {
        ZStack(alignment: .bottom) {
            FolkloreMapView(groups: vm.pinGroups, onSelectGroup: { group in
                selectedGroup = group
            })
            .ignoresSafeArea(edges: .top)

            if vm.isLoading {
                ProgressView("설화 로딩 중...")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)
            }
        }
        .animation(.spring(response: 0.3), value: selectedGroup?.id)
        .task { await vm.loadAllPins() }
        // 단일 핀 → 팝업 카드
        .sheet(item: $selectedPin) { pin in
            FolkloreDetailView(pin: pin)
                .presentationDetents([.medium, .large])
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
        let existing = mapView.annotations.compactMap { $0 as? GroupAnnotation }
        guard existing.count != groups.count else { return }
        mapView.removeAnnotations(existing)
        mapView.addAnnotations(groups.map { GroupAnnotation(group: $0) })
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FolkloreMapView

        init(_ parent: FolkloreMapView) { self.parent = parent }

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
