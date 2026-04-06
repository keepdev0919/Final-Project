import Foundation

enum Config {
    #if DEBUG
    static let baseURL = "http://localhost:8000"
    #else
    static let baseURL = "https://api.jejufolklore.com"
    #endif
}
