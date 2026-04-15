import SwiftUI
import MapKit
import SwiftData

struct CoursePreviewView: View {
    let course: Course
    @StateObject private var vm: CoursePreviewViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var navigateToExplore = false

    init(course: Course) {
        self.course = course
        _vm = StateObject(wrappedValue: CoursePreviewViewModel(course: course))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            courseMap
            bottomSheet
            if vm.showSavedToast {
                toastView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: vm.showSavedToast)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToExplore) {
            ExploreView(course: course, transport: "car")
        }
    }

    private var courseMap: some View {
        let coords = course.places.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let center = coords.first ?? CLLocationCoordinate2D(latitude: 33.3617, longitude: 126.5292)
        return Map(coordinateRegion: .constant(
            MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        ), annotationItems: course.places.enumerated().map { IndexedPlace(index: $0.offset, place: $0.element) }) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.place.lat, longitude: item.place.lng)) {
                NumberedMarker(number: item.index + 1)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            ScrollView(.vertical) {
                VStack(spacing: 12) {
                    if !course.narrative.isEmpty {
                        NarrativeCard(text: course.narrative)
                    }
                    ForEach(Array(course.places.enumerated()), id: \.offset) { idx, place in
                        PlaceCard(index: idx + 1, place: place)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 380)

            HStack(spacing: 12) {
                Button("다시 추천") {}
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button(vm.isSaved ? "저장됨" : "코스 저장") {
                    vm.save(context: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isSaved)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var toastView: some View {
        Text("코스가 저장됐어요!")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Helpers
struct IndexedPlace: Identifiable {
    let id: Int
    let index: Int
    let place: CoursePlace
    init(index: Int, place: CoursePlace) {
        self.id = index
        self.index = index
        self.place = place
    }
}

struct NumberedMarker: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Color.orange)
            .clipShape(Circle())
            .shadow(radius: 3)
    }
}

struct NarrativeCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("여행 이야기")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(4)
        }
        .padding(14)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PlaceCard: View {
    let index: Int
    let place: CoursePlace

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NumberedMarker(number: index)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                if let pin = place.folklorePins.first {
                    Text(pin.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
