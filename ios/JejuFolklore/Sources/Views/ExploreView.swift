// ios/JejuFolklore/Sources/Views/ExploreView.swift
import SwiftUI
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String
    let categoryScores: [String: Int]

    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    @State private var hasStopped = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    init(course: Course, transport: String, categoryScores: [String: Int] = [:]) {
        self.course = course
        self.transport = transport
        self.categoryScores = categoryScores
        _vm = StateObject(wrappedValue: ExploreViewModel(
            course: course,
            transport: transport,
            categoryScores: categoryScores
        ))
    }

    var body: some View {
        ZStack {
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

            VStack {
                Spacer()
                #if DEBUG
                Button("🐞 다음 장소 도착") { vm.simulateNextArrival() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .padding(.bottom, 8)
                #endif
                statusBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
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
        .onAppear { vm.startExploring() }
        .onDisappear { if !hasStopped { vm.stopExploring() } }
        .sheet(isPresented: $vm.showCompanionChat) {
            if let place = vm.activeChatPlace {
                CompanionChatView(place: place, companion: vm.companion, vm: vm)
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
                    visitedPlaces: vm.orderedVisitedPlaceNames,
                    companion: vm.companion,
                    onDone: { vm.showJournal = false }
                )
            }
        }
    }

    // MARK: - Map (iOS 17+)

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
                    NumberedMarker(number: i + 1, hasfolklore: !place.folklorePins.isEmpty)
                        .opacity(isVisited ? 0.35 : 1.0)
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

    // MARK: - Status Bar

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
        let by = transport == "walk" ? "FOOT" : "CAR"
        let kakaoStr = "kakaomap://route?ep=\(place.lat),\(place.lng)&by=\(by)"
        let appleStr = "maps://?daddr=\(place.lat),\(place.lng)&dirflg=\(transport == "walk" ? "w" : "d")"
        guard let kakaoURL = URL(string: kakaoStr), let appleURL = URL(string: appleStr) else { return }
        if UIApplication.shared.canOpenURL(kakaoURL) {
            UIApplication.shared.open(kakaoURL)
        } else {
            UIApplication.shared.open(appleURL)
        }
    }

    private var statusBar: some View {
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

            // 카카오맵 길찾기 버튼
            if let next = nextUnvisitedPlace {
                Button {
                    openNavigation(to: next)
                } label: {
                    Image(systemName: "map.fill")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .foregroundColor(.primary)
            }

            // 동행자 대화 버튼
            if let currentPlace = vm.lastArrivedPlace {
                Button {
                    vm.openCompanionChat(for: currentPlace)
                } label: {
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
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
