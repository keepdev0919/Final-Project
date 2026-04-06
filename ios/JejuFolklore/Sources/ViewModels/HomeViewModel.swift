import Foundation
import MapKit
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [Pin] = []
    @Published var selectedPin: Pin?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var lastFetchCenter: CLLocationCoordinate2D?
    private var fetchTask: Task<Void, Never>?

    // 지도 이동 후 핀 로드 (디바운스 적용)
    func onMapRegionChanged(center: CLLocationCoordinate2D, radiusM: Double) {
        // 이전 fetch와 거리 비교 — 200m 이상 이동 시에만 재요청
        if let last = lastFetchCenter {
            let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let curr = CLLocation(latitude: center.latitude, longitude: center.longitude)
            if prev.distance(from: curr) < 200 { return }
        }

        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초 디바운스
            guard !Task.isCancelled else { return }
            await loadPins(lat: center.latitude, lng: center.longitude, radiusM: radiusM)
        }
    }

    private func loadPins(lat: Double, lng: Double, radiusM: Double) async {
        isLoading = true
        lastFetchCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        do {
            pins = try await PinsAPI.fetch(lat: lat, lng: lng, radiusM: min(radiusM, 10000))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func selectPin(_ pin: Pin?) {
        selectedPin = pin
    }
}
