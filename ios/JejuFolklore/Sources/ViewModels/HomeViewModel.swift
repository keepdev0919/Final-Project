import Foundation
import MapKit

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pins: [Pin] = []
    @Published var selectedPin: Pin?
    @Published var isLoading = false
    @Published var errorMessage: String?

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

    func selectPin(_ pin: Pin?) {
        selectedPin = pin
    }
}
