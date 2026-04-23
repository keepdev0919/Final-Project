import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var visitedPlaceIDs: Set<String> = []

    var onArrival: ((String, Pin?) -> Void)?  // (placeName, firstPin)

    // 탐험 중인 코스 장소 목록
    private var activePlaces: [CoursePlace] = []
    private var transportMode: String = "car"  // "car" | "walk"
    private var pendingArrivals: [String: Date] = [:]
    private let dwellRequired: TimeInterval = 30

    private var arrivalRadius: Double {
        transportMode == "walk" ? 100.0 : 300.0
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startExploring(places: [CoursePlace], transport: String) {
        activePlaces = places
        transportMode = transport
        visitedPlaceIDs.removeAll()
        pendingArrivals.removeAll()
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stopExploring() {
        activePlaces = []
        pendingArrivals.removeAll()
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    private func checkArrival(for location: CLLocation) {
        for place in activePlaces {
            let placeID = "\(place.name)-\(place.day)"
            guard !visitedPlaceIDs.contains(placeID) else { continue }

            let target = CLLocation(latitude: place.lat, longitude: place.lng)
            let distance = location.distance(from: target)

            if distance <= arrivalRadius {
                if let enteredAt = pendingArrivals[placeID] {
                    if Date().timeIntervalSince(enteredAt) >= dwellRequired {
                        visitedPlaceIDs.insert(placeID)
                        pendingArrivals.removeValue(forKey: placeID)
                        onArrival?(place.name, place.folklorePins.first)
                    }
                } else {
                    pendingArrivals[placeID] = Date()
                }
            } else {
                pendingArrivals.removeValue(forKey: placeID)
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.checkArrival(for: location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
