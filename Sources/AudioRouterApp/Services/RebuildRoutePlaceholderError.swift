import Foundation

enum RebuildRoutePlaceholderError: LocalizedError {
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case let .notImplemented(message):
            return "重实现路线占位：\(message)"
        }
    }
}
