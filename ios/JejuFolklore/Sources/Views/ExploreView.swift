// ios/JejuFolklore/Sources/Views/ExploreView.swift
import SwiftUI
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String
    let categoryScores: [String: Int]

    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    init(course: Course, transport: String, categoryScores: [String: Int]) {
        self.course = course
        self.transport = transport
        self.categoryScores = categoryScores
        _vm = StateObject(wrappedValue: ExploreViewModel(
            course: course,
            transport: transport,
            categoryScores: categoryScores
        ))
    }

    @State private var hasStopped = false

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
                    Task { await vm.generateJournal() }
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

    // MARK: - Map

    private var exploreMap: some View {
        let userCoord = location.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292)
        return Map(
            coordinateRegion: .constant(
                MKCoordinateRegion(
                    center: userCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            ),
            showsUserLocation: true,
            annotationItems: course.places.enumerated().map { IndexedPlace(index: $0.offset, place: $0.element) }
        ) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng)) {
                let isVisited = vm.visitedPlaceNames.contains(item.place.name)
                NumberedMarker(number: item.index + 1, hasfolklore: !item.place.folklorePins.isEmpty)
                    .opacity(isVisited ? 0.35 : 1.0)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("방문 \(vm.visitedPlaceNames.count) / \(course.places.count)곳")
                    .font(.headline)
                if let next = course.places.first(where: { !vm.visitedPlaceNames.contains($0.name) }) {
                    Text("다음: \(next.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("모든 장소를 방문했어요!")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
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
