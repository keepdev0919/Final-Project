import SwiftUI
import MapKit

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292), // 제주도 중심
        span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            map
            if let pin = vm.selectedPin {
                PinPopupCard(pin: pin) {
                    vm.selectPin(nil)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
            }
        }
        .animation(.spring(response: 0.3), value: vm.selectedPin?.id)
        .ignoresSafeArea(edges: .top)
    }

    private var map: some View {
        Map(coordinateRegion: $region,
            showsUserLocation: true,
            annotationItems: vm.pins) { pin in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)) {
                PinMarkerView(pin: pin, isSelected: vm.selectedPin?.id == pin.id)
                    .onTapGesture { vm.selectPin(pin) }
            }
        }
        .onAppear {
            LocationService.shared.requestWhenInUseAuthorization()
        }
        .onChange(of: region.center.latitude) { _ in
            let radiusM = regionRadiusMeters(region)
            vm.onMapRegionChanged(center: region.center, radiusM: radiusM)
        }
    }

    private func regionRadiusMeters(_ region: MKCoordinateRegion) -> Double {
        let loc1 = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let loc2 = CLLocation(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                              longitude: region.center.longitude + region.span.longitudeDelta / 2)
        return loc1.distance(from: loc2)
    }
}

// MARK: - PinMarkerView
struct PinMarkerView: View {
    let pin: Pin
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(pin.sourceType == "legend" ? Color.orange : Color.purple)
                .clipShape(Circle())
                .scaleEffect(isSelected ? 1.3 : 1.0)
                .shadow(radius: isSelected ? 6 : 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 6))
                .foregroundColor(pin.sourceType == "legend" ? .orange : .purple)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
        .animation(.spring(response: 0.2), value: isSelected)
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
                        .background(pin.sourceType == "legend" ? Color.orange.opacity(0.15) : Color.purple.opacity(0.15))
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
        .contentShape(Rectangle())
    }
}
