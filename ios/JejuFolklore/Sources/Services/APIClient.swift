import Foundation
import FirebaseAuth

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(Int)
    case decodingFailed(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 URL입니다."
        case .invalidResponse(let code): return "서버 오류 (\(code))"
        case .decodingFailed: return "데이터 파싱에 실패했습니다."
        case .networkError(let e): return e.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private init() {}

    /// Firebase Auth 의 현재 사용자 ID 토큰을 비동기로 가져온다.
    /// - Firebase가 구성되지 않았거나 로그인되지 않은 경우 nil을 반환한다.
    private func currentIDToken() async -> String? {
        guard FirebaseAuth.Auth.auth().app != nil else { return nil }
        guard let user = Auth.auth().currentUser else { return nil }
        return try? await user.getIDToken()
    }

    /// 요청 직전에 Authorization 헤더를 부착한다 (토큰이 있을 때만).
    private func attachAuthHeader(_ request: inout URLRequest) async {
        if let token = await currentIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: Config.baseURL + path)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        await attachAuthHeader(&request)
        return try await perform(request)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: Config.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        await attachAuthHeader(&request)
        return try await perform(request)
    }

    func postData<B: Encodable>(_ path: String, body: B) async throws -> Data {
        guard let url = URL(string: Config.baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        await attachAuthHeader(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.invalidResponse(code)
        }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.invalidResponse(code)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}

// MARK: - Place Reviews
extension APIClient {
    func submitReview(placeName: String, tags: [String], note: String?) async {
        let body = PlaceReviewBody(
            placeName: placeName,
            tags: tags,
            note: note,
            deviceId: DeviceIdentity.shared.id
        )
        _ = try? await postData("/place/review", body: body)
    }

    func fetchReviews(placeName: String) async throws -> PlaceReviewsResponse {
        let encoded = placeName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeName
        return try await get("/place/reviews/\(encoded)")
    }
}
