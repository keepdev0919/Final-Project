import Foundation

enum Config {
    #if DEBUG
    static let baseURL = "http://192.168.35.27:8000"
    #else
    static let baseURL = "https://api.jejufolklore.com"
    #endif
}
