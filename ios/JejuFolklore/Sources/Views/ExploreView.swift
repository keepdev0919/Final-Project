import SwiftUI
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String
    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    init(course: Course, transport: String) {
        self.course = course
        self.transport = transport
        _vm = StateObject(wrappedValue: ExploreViewModel(course: course, transport: transport))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            exploreMap
            statusBar
        }
        .navigationTitle("탐험 중")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("종료") { vm.stopExploring() }
                    .foregroundColor(.red)
            }
        }
        .onAppear { vm.startExploring() }
        .onDisappear { vm.stopExploring() }
        .sheet(isPresented: $vm.showFolkloreDetail) {
            if let pin = vm.arrivedPin {
                FolkloreDetailView(pin: pin)
            }
        }
    }

    private var exploreMap: some View {
        let userCoord = location.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292)
        return Map(coordinateRegion: .constant(
            MKCoordinateRegion(center: userCoord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        ), showsUserLocation: true,
           annotationItems: course.places.enumerated().map { IndexedPlace(index: $0.offset, place: $0.element) }) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng)) {
                let isVisited = vm.visitedPlaceNames.contains(item.place.name)
                NumberedMarker(number: item.index + 1)
                    .opacity(isVisited ? 0.4 : 1.0)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("방문 \(vm.visitedPlaceNames.count) / \(course.places.count)곳")
                    .font(.headline)
                if let next = course.places.first(where: { !vm.visitedPlaceNames.contains($0.name) }) {
                    Text("다음: \(next.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let pin = vm.arrivedPin {
                Button("설화 보기") { vm.showFolkloreDetail = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
