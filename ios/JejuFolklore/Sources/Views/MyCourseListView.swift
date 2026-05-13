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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.title)
                .font(.subheadline.weight(.semibold))
            HStack {
                Label("\(course.durationDays)일", systemImage: "calendar")
                Label("\(course.places.count)개 장소", systemImage: "mappin")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if course.hasExploration {
                HStack(spacing: 6) {
                    Text("🎨 탐험 완료")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                    if let exploredAt = course.exploredAt {
                        Text(Self.dateFormatter.string(from: exploredAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SavedCourseDetailView: View {
    let course: SavedCourse
    @State private var startExplore = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일"
        return f
    }()

    private var journalUIImage: UIImage? {
        guard let data = course.journalImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 코스 장소 목록
                    VStack(alignment: .leading, spacing: 8) {
                        Text("코스 장소")
                            .font(.headline)
                            .padding(.horizontal, 16)
                        VStack(spacing: 0) {
                            ForEach(Array(course.places.enumerated()), id: \.offset) { idx, place in
                                placeRow(index: idx + 1, place: place)
                                if idx < course.places.count - 1 {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // 탐험 기록 (있을 때만)
                    if course.hasExploration {
                        explorationSection
                    }

                    // 탐험 시작 / 다시 보기 버튼
                    Button(course.hasExploration ? "다시 탐험하기" : "탐험 시작") {
                        startExplore = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .padding(.vertical, 16)
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

    private func placeRow(index: Int, place: CoursePlace) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
            }
            Text(place.name)
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var explorationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("여행 일지")
                    .font(.headline)
                Spacer()
                if let exploredAt = course.exploredAt {
                    Text(Self.dateFormatter.string(from: exploredAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                // 민화 이미지
                if let image = journalUIImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // 일지 텍스트
                if let text = course.journalText, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 방문한 장소들
                if let visited = course.visitedPlaceNames, !visited.isEmpty {
                    Divider()
                    Text("방문한 장소")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(visited, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(name)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}
