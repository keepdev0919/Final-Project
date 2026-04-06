import SwiftUI
import SwiftData

struct MyCourseListView: View {
    @Query(sort: \SavedCourse.savedAt, order: .reverse) private var courses: [SavedCourse]
    @State private var selectedCourse: SavedCourse?

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "저장된 코스가 없어요",
                        systemImage: "map",
                        description: Text("코스를 추천받고 저장해보세요")
                    )
                } else {
                    List(courses) { course in
                        SavedCourseRow(course: course)
                            .onTapGesture { selectedCourse = course }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("내 코스")
            .sheet(item: $selectedCourse) { course in
                SavedCourseDetailView(course: course)
            }
        }
    }
}

struct SavedCourseRow: View {
    let course: SavedCourse
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.title)
                .font(.subheadline.weight(.semibold))
            HStack {
                Label("\(course.durationDays)일", systemImage: "calendar")
                Label("\(course.places.count)개 장소", systemImage: "mappin")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SavedCourseDetailView: View {
    let course: SavedCourse
    @State private var startExplore = false

    var body: some View {
        NavigationStack {
            VStack {
                List(course.places) { place in
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.orange)
                        Text(place.name)
                    }
                }
                .listStyle(.insetGrouped)

                Button("탐험 시작") { startExplore = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .navigationTitle(course.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $startExplore) {
                ExploreView(
                    course: Course(
                        id: course.id,
                        title: course.title,
                        durationDays: course.durationDays,
                        places: course.places,
                        estimatedMinutes: course.estimatedMinutes
                    ),
                    transport: "car"
                )
            }
        }
    }
}
