import Foundation

/// 풀스크린 스토리 뷰어에서 사용하는 모델.
/// 한 설화(codeNo) 가 특정 장소(place) 컨텍스트에서 5~7 페이지로 가공된 형태.
struct FolkloreStory: Codable, Equatable {
    let codeNo: String
    let place: String
    let pages: [StoryPage]
}

struct StoryPage: Codable, Equatable, Identifiable {
    let title: String
    let body: String

    var id: String { title + "|" + body.prefix(20) }
}

/// 백엔드 응답 디코딩용 (pages 만 들어오는 케이스).
struct FolkloreStoryResponse: Codable {
    let pages: [StoryPage]
}

/// 연결 한 줄 응답 디코딩용.
struct FolkloreConnectionResponse: Codable {
    let connection: String
}
