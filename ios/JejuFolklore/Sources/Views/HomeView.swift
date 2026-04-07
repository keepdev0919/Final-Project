import SwiftUI
import MapKit

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            FolkloreMapView(pins: vm.pins, selectedPin: $vm.selectedPin)
                .ignoresSafeArea(edges: .top)

            if vm.isLoading {
                ProgressView("설화 로딩 중...")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)
            }

            if let pin = vm.selectedPin {
                PinPopupCard(pin: pin) { vm.selectPin(nil) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .animation(.spring(response: 0.3), value: vm.selectedPin?.id)
        .task { await vm.loadAllPins() }
    }
}

// MARK: - FolkloreAnnotation

final class FolkloreAnnotation: NSObject, MKAnnotation {
    let pin: Pin
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
    }
    var title: String? { pin.title }
    var subtitle: String? { pin.primaryPlace }

    init(pin: Pin) { self.pin = pin }
}

// MARK: - FolkloreMapView (UIViewRepresentable)

struct FolkloreMapView: UIViewRepresentable {
    let pins: [Pin]
    @Binding var selectedPin: Pin?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        let center = CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        mapView.setRegion(region, animated: false)

        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "pin"
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        LocationService.shared.requestWhenInUseAuthorization()
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let existing = mapView.annotations.compactMap { $0 as? FolkloreAnnotation }
        guard existing.count != pins.count else { return }
        mapView.removeAnnotations(existing)
        mapView.addAnnotations(pins.map { FolkloreAnnotation(pin: $0) })
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FolkloreMapView

        init(_ parent: FolkloreMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // 클러스터 배지
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView
                view?.markerTintColor = .systemOrange
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }

            // 개별 핀
            if let folklore = annotation as? FolkloreAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "pin",
                    for: folklore
                ) as? MKMarkerAnnotationView
                let isLegend = folklore.pin.sourceType == "legend"
                view?.markerTintColor = isLegend ? .systemOrange : .systemPurple
                view?.glyphImage = UIImage(systemName: isLegend ? "book.fill" : "mic.fill")
                view?.clusteringIdentifier = "folklore"
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // 클러스터 탭 → 해당 멤버들이 다 보이도록 줌인
            if let cluster = view.annotation as? MKClusterAnnotation {
                var rect = MKMapRect.null
                for annotation in cluster.memberAnnotations {
                    let point = MKMapPoint(annotation.coordinate)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
                }
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40),
                    animated: true
                )
                return
            }

            // 개별 핀 탭 → 팝업
            if let folklore = view.annotation as? FolkloreAnnotation {
                parent.selectedPin = folklore.pin
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            // 팝업은 dismiss 버튼으로만 닫음
        }
    }
}

// MARK: - PinPopupCard

struct PinPopupCard: View {
    let pin: Pin
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.sourceTypeLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            pin.sourceType == "legend"
                                ? Color.orange.opacity(0.15)
                                : Color.purple.opacity(0.15)
                        )
                        .foregroundColor(pin.sourceType == "legend" ? .orange : .purple)
                        .clipShape(Capsule())
                    Text(pin.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            if !pin.summary.isEmpty && pin.summary != pin.title {
                Text(pin.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            if !pin.primaryPlace.isEmpty {
                Label(pin.primaryPlace, systemImage: "mappin")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("더 보기") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}
