import Foundation

// MARK: - Synthesis models

struct SynthesisItem: Identifiable {
    let id = UUID()
    let text: String
}

struct SynthesisDisagreement: Identifiable {
    let id = UUID()
    let topic: String
    let positions: [(model: String, position: String)]
}

struct SynthesisUniquePoint: Identifiable {
    let id = UUID()
    let claim: String
    let source: String
}

struct SynthesisResult {
    let consensus: [SynthesisItem]
    let disagreements: [SynthesisDisagreement]
    let unique: [SynthesisUniquePoint]
    let suspicious: [SynthesisItem]

    var isEmpty: Bool {
        consensus.isEmpty && disagreements.isEmpty && unique.isEmpty && suspicious.isEmpty
    }
}

enum SynthesisState {
    case idle
    case synthesizing
    case success(SynthesisResult)
    case failed(String)
}

// MARK: - Compare models

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
