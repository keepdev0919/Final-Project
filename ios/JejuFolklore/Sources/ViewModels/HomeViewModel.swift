import Foundation
import MapKit

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [Pin] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var pinGroups: [PinGroup] {
        Dictionary(grouping: pins, by: { "\(round($0.lat * 10000) / 10000)-\(round($0.lng * 10000) / 10000)" })
            .values
            .map { PinGroup(pins: $0) }
    }

    func loadAllPins() async {
        guard pins.isEmpty else { return }
        isLoading = true
        do {
            pins = try await PinsAPI.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
