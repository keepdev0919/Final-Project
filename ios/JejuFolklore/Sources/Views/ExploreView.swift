// ios/JejuFolklore/Sources/Views/ExploreView.swift
import SwiftUI
import SwiftData
import MapKit

struct ExploreView: View {
    let course: Course
    let transport: String

    @StateObject private var vm: ExploreViewModel
    @StateObject private var location = LocationService.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedCourses: [SavedCourse]

    @State private var hasStopped = false
    @State private var explorationCompleted = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedPlace: CoursePlace?
    @State private var isListExpanded = true
    @State private var reviewTargetPlace: CoursePlace? = nil
    @State private var showPlaceReview = false
    @State private var selectedDay: Int? = nil

    // 전체 day 목록 (중복 제거, 정렬)
    private var days: [Int] {
        Array(Set(course.places.map { $0.day })).sorted()
    }

    // day 기준으로 장소 그룹핑
    private var placesByDay: [Int: [CoursePlace]] {
        Dictionary(grouping: course.places, by: { $0.day })
    }

    /// day 섹션의 첫 번째 장소가 전체 places 배열에서 갖는 오프셋 (마커 번호용)
    private func globalOffset(for day: Int) -> Int {
        guard let firstPlace = placesByDay[day]?.first else { return 0 }
        let idx = course.places.firstIndex { p in
            p.name == firstPlace.name && p.day == firstPlace.day
        }
        return idx ?? 0
    }
    init(course: Course, transport: String) {
        self.course = course
        self.transport = transport
        _vm = StateObject(wrappedValue: ExploreViewModel(
            course: course,
            transport: transport
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            exploreMap
                .ignoresSafeArea(edges: .top)

            if vm.showArrivalOverlay, let place = vm.arrivedPlace {
                ArrivalOverlayView(
                    place: place,
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
                    explorationCompleted = true
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
        // ⚠️ 장소 리뷰는 현재 진입 경로가 없다. 예전에는 설화 채팅을 닫을 때
        // 떴는데, 채팅을 제거(2026-08-13)하면서 트리거가 사라졌다. 도착 직후에
        // 리뷰를 묻는 것은 어색하므로 억지로 붙이지 않고, 단계 1에서 "이야기를
        // 다 들은 뒤"에 연결한다. 그때까지 이 시트는 도달 불가 상태다.
        //
        // 파급: 이 시트가 유일한 사용처였던 것들도 함께 클라이언트 0이 된다.
        //   - Services/SpeechRecognizer.swift (음성 받아쓰기)
        //   - backend/routers/review.py (POST /place/review, GET /place/reviews/{name})
        // 셋 다 단계 1에서 함께 되살아난다. 죽은 코드로 보고 지우지 말 것.
        .sheet(isPresented: $showPlaceReview) {
            if let place = reviewTargetPlace {
                PlaceReviewSheet(
                    placeName: place.name,
                    onDone: {
                        showPlaceReview = false
                        reviewTargetPlace = nil
                    }
                )
            }
        }
        .onChange(of: explorationCompleted) {
            if explorationCompleted {
                Task {
                    await archiveExploration()
                    await MainActor.run {
                        // 탐험 완료 후 "내 코스" 탭으로 자동 전환.
                        // 1) AppStorage 먼저 변경 → 부모가 dismiss될 때 이미 탭 전환 완료 상태.
                        // 2) NotificationCenter post → 부모 view들(CoursePreviewView,
                        //    SavedCourseDetailView)이 받아서 자신도 dismiss → TabView root 도달.
                        // 3) 마지막으로 자신을 dismiss().
                        UserDefaults.standard.set(AppTab.course.rawValue, forKey: "selected_tab")
                        // 방금 완료한 코스 ID를 저장 → MyCourseListView.onAppear가 읽고 스크롤+하이라이트.
                        UserDefaults.standard.set(course.id, forKey: "just_completed_course_id")
                        TravelStore.shared.clear()
                        NotificationCenter.default.post(name: .exploreDidComplete, object: nil)
                        dismiss()
                    }
                }
            }
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
                    NumberedMarker(number: i + 1)
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

                // Day 탭 필터 (2일 이상일 때만 표시)
                if days.count > 1 {
                    dayTabBar
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if days.count > 1 {
                            // Day 섹션별 장소 목록 (다일 코스)
                            ForEach(days, id: \.self) { day in
                                if selectedDay == nil || selectedDay == day {
                                    ExploreDaySectionView(
                                        day: day,
                                        places: placesByDay[day] ?? [],
                                        globalOffset: globalOffset(for: day),
                                        visitedPlaceNames: vm.visitedPlaceNames,
                                        onPlaceTap: { selectedPlace = $0 }
                                    )
                                }
                            }
                        } else {
                            // 1일 코스 — 기존 flat 표시 유지
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
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        #if DEBUG
                        Button("🐞 다음 장소 도착") { vm.simulateNextArrival() }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .padding(.top, 4)
                            .padding(.bottom, 10)
                        #endif
                    }
                }
                .frame(maxHeight: 280)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Day Tab Bar

    private var dayTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ExploreDayTabButton(title: "전체", isSelected: selectedDay == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDay = nil }
                }
                ForEach(days, id: \.self) { day in
                    ExploreDayTabButton(title: "Day \(day)", isSelected: selectedDay == day) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = (selectedDay == day) ? nil : day
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
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

        }
    }

    // MARK: - Exploration Archive

    /// 탐험 완료 시 SavedCourse(SwiftData)에 방문 장소와 완료 시각을 영구 저장한다.
    /// - 기존 코스(같은 id)가 있으면 갱신, 없으면 새 SavedCourse를 생성해서 insert.
    /// - 단계 1의 픽셀아트 기록 화면이 이 데이터를 읽는다.
    private func archiveExploration() async {
        let visitedPlaces = vm.orderedVisitedPlaceNames

        // 같은 id가 이미 SavedCourse로 있는지 검색 (수동 필터 — predicate가 없어도 충분)
        let targetId = course.id
        await MainActor.run {
            let existing = savedCourses.first(where: { $0.id == targetId })
            if let existing {
                existing.recordExploration(visitedPlaces: visitedPlaces)
            } else {
                let newSaved = SavedCourse(from: course)
                newSaved.recordExploration(visitedPlaces: visitedPlaces)
                modelContext.insert(newSaved)
            }
            try? modelContext.save()
        }
    }

}

// MARK: - ExploreDaySectionView

/// ExploreView 전용 Day 섹션 뷰. 방문 완료 체크마크 + 탭 액션을 포함.
private struct ExploreDaySectionView: View {
    let day: Int
    let places: [CoursePlace]
    let globalOffset: Int   // 전체 배열에서의 시작 번호 오프셋
    let visitedPlaceNames: Set<String>
    let onPlaceTap: (CoursePlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            HStack {
                Text("Day \(day)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 장소 카드 목록
            ForEach(Array(places.enumerated()), id: \.offset) { idx, place in
                let isVisited = visitedPlaceNames.contains(place.name)
                PlaceCard(index: globalOffset + idx + 1, place: place)
                    .opacity(isVisited ? 0.45 : 1.0)
                    .overlay(alignment: .topTrailing) {
                        if isVisited {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                                .padding(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onTapGesture { onPlaceTap(place) }
            }
        }
    }
}

// MARK: - ExploreDayTabButton

private struct ExploreDayTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.orange : Color.orange.opacity(0.1))
                .foregroundColor(isSelected ? .white : .orange)
                .clipShape(Capsule())
        }
    }
}
