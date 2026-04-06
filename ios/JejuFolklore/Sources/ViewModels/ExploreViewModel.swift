import Foundation
import UserNotifications

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var visitedPlaceNames: Set<String> = []
    @Published var arrivedPin: Pin?
    @Published var showFolkloreDetail = false

    let course: Course
    let transport: String

    init(course: Course, transport: String) {
        self.course = course
        self.transport = transport
    }

    func startExploring() {
        requestNotificationPermission()
        LocationService.shared.requestAlwaysAuthorization()
        LocationService.shared.onArrival = { [weak self] placeName, pin in
            Task { @MainActor [weak self] in
                self?.handleArrival(placeName: placeName, pin: pin)
            }
        }
        LocationService.shared.startExploring(places: course.places, transport: transport)
    }

    func stopExploring() {
        LocationService.shared.stopExploring()
        LocationService.shared.onArrival = nil
    }

    private func handleArrival(placeName: String, pin: Pin?) {
        visitedPlaceNames.insert(placeName)
        arrivedPin = pin
        sendArrivalNotification(placeName: placeName, pin: pin)
    }

    private func sendArrivalNotification(placeName: String, pin: Pin?) {
        let content = UNMutableNotificationContent()
        content.title = "📍 \(placeName) 도착"
        content.body = pin.map { "[\($0.sourceTypeLabel)] \($0.title)" } ?? "근처에 설화가 있어요"
        content.sound = .default

        let listenAction = UNNotificationAction(
            identifier: "LISTEN_TTS",
            title: "설화 듣기",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "ARRIVAL",
            actions: [listenAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "ARRIVAL"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
