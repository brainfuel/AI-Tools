import Foundation

enum AppError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case emptyReply
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Invalid request configuration."
        case .invalidResponse: return "Invalid server response."
        case .emptyReply: return "No text returned by the model."
        case .api(let message): return message
        }
    }
}
