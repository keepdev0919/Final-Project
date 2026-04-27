import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TasteDiscoveryView()
                .tabItem { Label("코스 만들기", systemImage: "sparkles") }
            MyCourseListView()
                .tabItem { Label("내 코스", systemImage: "bookmark.fill") }
#if DEBUG
            DebugExploreView()
                .tabItem { Label("테스트", systemImage: "ladybug.fill") }
            #endif
        }
        .tint(.orange)
    }
}

#if DEBUG
private let debugCourse = Course(
    id: "debug-course",
    title: "테스트 코스 (성산 → 섭지 → 협재)",
    durationDays: 1,
    places: [
        CoursePlace(name: "성산일출봉", lat: 33.4580, lng: 126.9425, day: 1),
        CoursePlace(name: "섭지코지",   lat: 33.4270, lng: 126.9307, day: 1),
        CoursePlace(name: "협재해수욕장", lat: 33.3942, lng: 126.2390, day: 1),
    ],
    estimatedMinutes: 180
)

struct DebugExploreView: View {
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("고정 테스트 코스")
                        .font(.headline)
                    ForEach(debugCourse.places) { place in
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundColor(.orange)
                            Text(place.name)
                            Spacer()
                            Text("(\(String(format: "%.4f", place.lat)), \(String(format: "%.4f", place.lng)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text("시뮬레이터 테스트 방법")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("Features > Location > Custom Location\n위 좌표를 순서대로 입력하세요.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                NavigationLink("탐험 시작") {
                    ExploreView(course: debugCourse, transport: "car", categoryScores: [:])
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .navigationTitle("🐞 디버그")
        }
    }
}
#endif
