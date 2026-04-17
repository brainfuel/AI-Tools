import Foundation

enum APIClientError: LocalizedError {
    case invalidRequest(provider: AIProvider)
    case invalidResponse(provider: AIProvider)
    case emptyReply(provider: AIProvider)
    case api(provider: AIProvider, statusCode: Int?, message: String)
    case transport(provider: AIProvider, urlError: URLError)

    var provider: AIProvider {
        switch self {
        case .invalidRequest(let provider),
             .invalidResponse(let provider),
             .emptyReply(let provider),
             .api(let provider, _, _),
             .transport(let provider, _):
            return provider
        }
    }

    var isRetryable: Bool {
        switch self {
        case .transport(_, let urlError):
            return Self.retryableTransportCodes.contains(urlError.code)
        case .api(_, let statusCode, _):
            guard let statusCode else { return false }
            return Self.retryableStatusCodes.contains(statusCode) || (500...599).contains(statusCode)
        case .invalidRequest, .invalidResponse, .emptyReply:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let provider):
            return "\(provider.displayName): Invalid request configuration."
        case .invalidResponse(let provider):
            return "\(provider.displayName): Invalid server response."
        case .emptyReply(let provider):
            return "\(provider.displayName): No text returned by the model."
        case .api(let provider, _, let message):
            return "\(provider.displayName): \(message)"
        case .transport(let provider, let urlError):
            return "\(provider.displayName): \(urlError.localizedDescription)"
        }
    }
}

extension APIClientError {
    static func fromHTTP(
        provider: AIProvider,
        statusCode: Int,
        message: String?,
        fallbackPrefix: String
    ) -> APIClientError {
        let normalizedMessage = normalizedMessage(message) ?? "\(fallbackPrefix) \(statusCode)."
        return .api(provider: provider, statusCode: statusCode, message: normalizedMessage)
    }

    static func normalize(_ error: Error, provider: AIProvider) -> APIClientError {
        if let typed = error as? APIClientError { return typed }
        if let urlError = error as? URLError { return .transport(provider: provider, urlError: urlError) }

        if error is DecodingError {
            return .invalidResponse(provider: provider)
        }

        return .api(provider: provider, statusCode: nil, message: error.localizedDescription)
    }

    static func message(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func normalizedMessage(_ message: String?) -> String? {
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static let retryableStatusCodes: Set<Int> = [408, 409, 425, 429]
    private static let retryableTransportCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .resourceUnavailable
    ]
}
