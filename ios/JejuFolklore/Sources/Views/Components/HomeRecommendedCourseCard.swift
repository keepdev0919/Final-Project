import SwiftUI

/// 홈 하단 "당신을 위한 코스 추천" 가로 스크롤용 카드.
struct HomeRecommendedCourseCard: View {
    let course: Course
    let previewImage: String?
    let onTap: () -> Void

    /// 전체 장소 개수
    private var placeCount: Int { course.places.count }

    /// 첫 장소 2개 미리보기
    private var previewPlaces: [CoursePlace] {
        Array(course.places.prefix(2))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                imageHeader
                infoBody
            }
            .frame(width: 240)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image

    private var imageHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlString = previewImage,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            placeholder.overlay(ProgressView().tint(.white))
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 240, height: 130)
            .clipped()

            // 일정 라벨 (좌하단)
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text("\(course.durationDays)일 · 장소 \(placeCount)곳")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
            .padding(10)
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: gradientForCourse(course.id),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "map.fill")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.7))
        )
    }

    /// 코스 id 해시로 다른 그라데이션 색 부여 (이미지 없을 때 단조로움 방지)
    private func gradientForCourse(_ id: String) -> [Color] {
        let palettes: [[Color]] = [
            [.orange, .pink],
            [.orange.opacity(0.85), Color(red: 0.95, green: 0.45, blue: 0.3)],
            [Color(red: 1.0, green: 0.55, blue: 0.3), .yellow.opacity(0.85)]
        ]
        let idx = abs(id.hashValue) % palettes.count
        return palettes[idx]
    }

    // MARK: - Info

    private var infoBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !previewPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(previewPlaces) { place in
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(place.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if placeCount > 2 {
                        Text("외 \(placeCount - 2)곳")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .frame(height: 96, alignment: .top)
    }
}
