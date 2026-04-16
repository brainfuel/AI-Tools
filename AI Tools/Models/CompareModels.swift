import Foundation

enum CompareResultState: String, Codable {
    case loading
    case success
    case failed
    case skipped
}

struct CompareProviderResult: Codable {
    var state: CompareResultState
    var modelID: String
    var text: String
    var generatedMedia: [GeneratedMedia]
    var inputTokens: Int
    var outputTokens: Int
    var errorMessage: String?
}

struct CompareRun: Identifiable, Codable {
    let id: UUID
    let prompt: String
    let attachments: [AttachmentSummary]
    let createdAt: Date
    var results: [AIProvider: CompareProviderResult]
}

struct CompareConversation: Identifiable, Codable {
    var id: UUID
    var title: String
    var updatedAt: Date
    var runs: [CompareRun]

    var searchBlob: String {
        let prompts = runs.map(\.prompt).joined(separator: "\n")
        let replies = runs.flatMap { run in
            run.results.values.map(\.text)
        }.joined(separator: "\n")
        return "\(title)\n\(prompts)\n\(replies)"
    }
}
