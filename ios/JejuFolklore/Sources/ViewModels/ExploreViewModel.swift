import Foundation
import UserNotifications

@MainActor
final class ExploreViewModel: ObservableObject {
    // Visit tracking
    @Published var visitedPlaceNames: Set<String> = []

    // Arrival overlay
    @Published var arrivedPlace: CoursePlace?
    @Published var lastArrivedPlace: CoursePlace?
    @Published var showArrivalOverlay = false

    // Companion chat
    @Published var activeChatPlace: CoursePlace?
    @Published var showCompanionChat = false

    // Travel journal
    @Published var journalText: String = ""
    @Published var isGeneratingJournal = false
    @Published var showJournal = false
    @Published var showDaySummary = false

    let course: Course
    let transport: String
    let companion: CompanionCharacter

    private var travelSession: TravelSession

    init(course: Course, transport: String, categoryScores: [String: Int]) {
        self.course = course
        self.transport = transport
        self.companion = CompanionCharacter.from(categoryScores: categoryScores)
        self.travelSession = TravelSession(courseId: course.id, companion: self.companion)
    }

    // MARK: - Explore lifecycle

    func startExploring() {
        requestNotificationPermission()
        LocationService.shared.requestAlwaysAuthorization()
        LocationService.shared.onArrival = { [weak self] placeName, pin in
            Task { @MainActor [weak self] in
                self?.handleArrival(placeName: placeName)
            }
        }
        LocationService.shared.startExploring(places: course.places, transport: transport)
    }

    func stopExploring() {
        LocationService.shared.stopExploring()
        LocationService.shared.onArrival = nil
        TravelStore.shared.save(travelSession)
    }

    // MARK: - Arrival handling

    #if DEBUG
    func simulateNextArrival() {
        guard let next = course.places.first(where: { !visitedPlaceNames.contains($0.name) }) else { return }
        handleArrival(placeName: next.name)
    }
    #endif

    private func handleArrival(placeName: String) {
        guard let place = course.places.first(where: { $0.name == placeName }) else { return }
        visitedPlaceNames.insert(placeName)
        if !travelSession.visitedPlaceNames.contains(placeName) {
            travelSession.visitedPlaceNames.append(placeName)
        }
        TravelStore.shared.save(travelSession)

        arrivedPlace = place
        lastArrivedPlace = place
        showArrivalOverlay = true
        sendArrivalNotification(placeName: placeName)
    }

    func dismissArrivalOverlay() {
        showArrivalOverlay = false
    }

    func openCompanionChat(for place: CoursePlace) {
        showArrivalOverlay = false
        activeChatPlace = place
        showCompanionChat = true
    }

    var orderedVisitedPlaceNames: [String] { travelSession.visitedPlaceNames }

    // MARK: - Chat persistence

    func messages(for placeName: String) -> [TravelChatMessage] {
        travelSession.chatLogs.first(where: { $0.placeName == placeName })?.messages ?? []
    }

    func appendMessage(_ msg: TravelChatMessage, to placeName: String) {
        travelSession.appendMessage(msg, to: placeName)
        TravelStore.shared.save(travelSession)
        objectWillChange.send()
    }

    // MARK: - Journal generation

    func generateJournal() async {
        isGeneratingJournal = true
        showJournal = true
        do {
            journalText = try await TravelAPI.generateJournal(session: travelSession)
        } catch {
            journalText = "여행 일지를 생성하지 못했어요. 나중에 다시 시도해주세요."
        }
        isGeneratingJournal = false
    }

    // MARK: - Notification

    private func sendArrivalNotification(placeName: String) {
        let content = UNMutableNotificationContent()
        content.title = "설화 장소에 도착했습니다"
        content.body = "\(placeName) — \(companion.displayName)가 기다리고 있어요"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
