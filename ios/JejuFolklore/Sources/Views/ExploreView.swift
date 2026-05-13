// ios/JejuFolklore/Sources/Views/ExploreView.swift
import SwiftUI
import SwiftData
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String
    let categoryScores: [String: Int]

    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedCourses: [SavedCourse]

    @State private var hasStopped = false
    @State private var journalCompleted = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedFolklorePlace: CoursePlace?
    @State private var selectedPlace: CoursePlace?
    @State private var isListExpanded = true
    @State private var reviewTargetPlace: CoursePlace? = nil
    @State private var showPlaceReview = false
    init(course: Course, transport: String, categoryScores: [String: Int] = [:], overrideCompanion: CompanionCharacter? = nil) {
        self.course = course
        self.transport = transport
        self.categoryScores = categoryScores
        _vm = StateObject(wrappedValue: ExploreViewModel(
            course: course,
            transport: transport,
            categoryScores: categoryScores,
            overrideCompanion: overrideCompanion
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            exploreMap
                .ignoresSafeArea(edges: .top)

            if vm.showArrivalOverlay, let place = vm.arrivedPlace {
                ArrivalOverlayView(
                    place: place,
                    companion: vm.companion,
                    onEnterChat: { vm.openCompanionChat(for: place) },
                    onDismiss: { vm.dismissArrivalOverlay() }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            exploreBottomSheet
        }
        .animation(.easeInOut(duration: 0.25), value: vm.showArrivalOverlay)
        .navigationTitle("탐험 중")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("탐험 마치기") {
                    hasStopped = true
                    vm.stopExploring()
                    vm.showDaySummary = true
                }
                .foregroundColor(.orange)
                .fontWeight(.semibold)
            }
        }
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        .onAppear { vm.startExploring() }
        .onDisappear { if !hasStopped { vm.stopExploring() } }
        .sheet(isPresented: $vm.showCompanionChat, onDismiss: {
            let place = vm.lastArrivedPlace
            vm.activeChatPlace = nil
            if let place {
                reviewTargetPlace = place
                showPlaceReview = true
            }
        }) {
            if let place = vm.activeChatPlace {
                CompanionChatView(place: place, companion: vm.companion, vm: vm)
            }
        }
        .sheet(isPresented: $showPlaceReview) {
            if let place = reviewTargetPlace {
                PlaceReviewSheet(
                    placeName: place.name,
                    companion: vm.companion,
                    onDone: {
                        showPlaceReview = false
                        reviewTargetPlace = nil
                    }
                )
            }
        }
        .sheet(isPresented: $vm.showDaySummary) {
            DaySummaryView(
                visitedPlaces: vm.orderedVisitedPlaceNames,
                companion: vm.companion,
                onGenerateJournal: {
                    vm.showDaySummary = false
                    Task { await vm.generateJournal() }
                },
                onDismiss: { vm.showDaySummary = false }
            )
        }
        .sheet(isPresented: $vm.showJournal) {
            if vm.isGeneratingJournal {
                JournalLoadingView(companion: vm.companion)
            } else {
                TravelJournalView(
                    journalText: vm.journalText,
                    imageURL: vm.journalImageURL,
                    visitedPlaces: vm.orderedVisitedPlaceNames,
                    companion: vm.companion,
                    onDone: {
                        journalCompleted = true
                        vm.showJournal = false
                    }
                )
            }
        }
        .onChange(of: journalCompleted) {
            if journalCompleted {
                Task {
                    await archiveExploration()
                    await MainActor.run {
                        // 탐험 완료 후 "내 코스" 탭으로 자동 전환
                        UserDefaults.standard.set(AppTab.myCourse.rawValue, forKey: "selected_tab")
                        TravelStore.shared.clear()
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedFolklorePlace) { place in
            FolklorePlacePinsView(place: place)
        }
    }

    // MARK: - Map

    private var placeCoordinates: [CLLocationCoordinate2D] {
        course.places.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    private var exploreMap: some View {
        Map(position: $mapPosition) {
            UserAnnotation()
            ForEach(course.places.indices, id: \.self) { i in
                let place = course.places[i]
                let isVisited = vm.visitedPlaceNames.contains(place.name)
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)) {
                    Button {
                        if !place.folklorePins.isEmpty {
                            selectedFolklorePlace = place
                        }
                    } label: {
                        NumberedMarker(number: i + 1, hasfolklore: !place.folklorePins.isEmpty)
                            .opacity(isVisited ? 0.35 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
            if placeCoordinates.count >= 2 {
                MapPolyline(coordinates: placeCoordinates)
                    .stroke(
                        .orange.opacity(0.75),
                        style: StrokeStyle(lineWidth: 3.5, dash: [8, 5])
                    )
            }
        }
    }

    // MARK: - Bottom Sheet

    private var exploreBottomSheet: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            Button {
                withAnimation(.spring(response: 0.35)) {
                    isListExpanded.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 4)
                    if !isListExpanded {
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, isListExpanded ? 4 : 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        withAnimation(.spring(response: 0.35)) {
                            if value.translation.height > 40 { isListExpanded = false }
                            else if value.translation.height < -40 { isListExpanded = true }
                        }
                    }
            )

            // 상태 요약 (항상 표시)
            statusRow
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // 접을 수 있는 장소 목록
            if isListExpanded {
                Divider()
                    .padding(.horizontal, 16)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(course.places.enumerated()), id: \.offset) { idx, place in
                            let isVisited = vm.visitedPlaceNames.contains(place.name)
                            PlaceCard(index: idx + 1, place: place)
                                .opacity(isVisited ? 0.45 : 1.0)
                                .overlay(alignment: .topTrailing) {
                                    if isVisited {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title3)
                                            .padding(10)
                                    }
                                }
                                .onTapGesture { selectedPlace = place }
                        }
                        #if DEBUG
                        Button("🐞 다음 장소 도착") { vm.simulateNextArrival() }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .padding(.top, 4)
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 280)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Status Row

    private var nextUnvisitedPlace: CoursePlace? {
        course.places.first { !vm.visitedPlaceNames.contains($0.name) }
    }

    private var distanceToNext: CLLocationDistance? {
        guard let userLoc = location.currentLocation,
              let next = nextUnvisitedPlace else { return nil }
        return userLoc.distance(from: CLLocation(latitude: next.lat, longitude: next.lng))
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        meters < 1000
            ? String(format: "%.0fm", meters)
            : String(format: "%.1fkm", meters / 1000)
    }

    private func openNavigation(to place: CoursePlace) {
        let mode = transport == "walk" ? "walking" : "driving"
        let googleAppStr = "comgooglemaps://?daddr=\(place.lat),\(place.lng)&directionsmode=\(mode)"
        let googleWebStr = "https://maps.google.com/maps?daddr=\(place.lat),\(place.lng)&directionsmode=\(mode)"
        guard let googleAppURL = URL(string: googleAppStr),
              let googleWebURL = URL(string: googleWebStr) else { return }
        if UIApplication.shared.canOpenURL(googleAppURL) {
            UIApplication.shared.open(googleAppURL)
        } else {
            UIApplication.shared.open(googleWebURL)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("방문 \(vm.visitedPlaceNames.count) / \(course.places.count)곳")
                    .font(.headline)
                if let next = nextUnvisitedPlace {
                    HStack(spacing: 4) {
                        Text("다음: \(next.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let dist = distanceToNext {
                            Text("· \(formattedDistance(dist))")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("모든 장소를 방문했어요!")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()

            if let next = nextUnvisitedPlace {
                Button { openNavigation(to: next) } label: {
                    Image(systemName: "map.fill")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .foregroundColor(.primary)
            }

            if let currentPlace = vm.lastArrivedPlace {
                Button { vm.openCompanionChat(for: currentPlace) } label: {
                    HStack(spacing: 4) {
                        Text(vm.companion.emoji)
                        Text("대화")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Exploration Archive

    /// 탐험 완료 시 SavedCourse(SwiftData)에 일지/이미지/방문 장소를 영구 저장한다.
    /// - 기존 코스(같은 id)가 있으면 갱신, 없으면 새 SavedCourse를 생성해서 insert.
    /// - 이미지 URL은 data:image/png;base64 형태 → 직접 디코딩, https → 다운로드.
    private func archiveExploration() async {
        let journalText = vm.journalText
        let visitedPlaces = vm.orderedVisitedPlaceNames
        let imageData = await loadJournalImageData(from: vm.journalImageURL)

        // 같은 id가 이미 SavedCourse로 있는지 검색 (수동 필터 — predicate가 없어도 충분)
        let targetId = course.id
        await MainActor.run {
            let existing = savedCourses.first(where: { $0.id == targetId })
            if let existing {
                existing.recordExploration(
                    journalText: journalText,
                    imageData: imageData,
                    visitedPlaces: visitedPlaces
                )
            } else {
                let newSaved = SavedCourse(from: course)
                newSaved.recordExploration(
                    journalText: journalText,
                    imageData: imageData,
                    visitedPlaces: visitedPlaces
                )
                modelContext.insert(newSaved)
            }
            try? modelContext.save()
        }
    }

    /// 일지 이미지 URL을 Data로 로드한다. 실패 시 nil.
    private func loadJournalImageData(from url: URL?) async -> Data? {
        guard let url else { return nil }
        let urlString = url.absoluteString

        // data:image/...;base64,... 처리
        if urlString.hasPrefix("data:") {
            if let commaIdx = urlString.firstIndex(of: ",") {
                let base64Part = String(urlString[urlString.index(after: commaIdx)...])
                return Data(base64Encoded: base64Part)
            }
            return nil
        }

        // 일반 http(s) 다운로드
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }
}
