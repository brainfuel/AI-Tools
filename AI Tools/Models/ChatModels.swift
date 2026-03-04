import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case gemini
    case chatGPT
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .chatGPT: return "ChatGPT"
        case .anthropic: return "Anthropic"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .gemini: return "Gemini API Key"
        case .chatGPT: return "OpenAI API Key"
        case .anthropic: return "Anthropic API Key"
        }
    }

    var isImplemented: Bool {
        switch self {
        case .gemini, .chatGPT, .anthropic: return true
        }
    }
}

extension AIProvider {
    static func inferredProvider(for modelID: String) -> AIProvider {
        let value = modelID.lowercased()

        if value.hasPrefix("gpt-") || value.hasPrefix("o1") || value.hasPrefix("o3") || value.hasPrefix("o4") || value.hasPrefix("dall-e") || value.hasPrefix("chatgpt-") {
            return .chatGPT
        }

        if value.hasPrefix("claude") {
            return .anthropic
        }

        return .gemini
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant

    var label: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        }
    }
}

struct AttachmentSummary: Identifiable, Codable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct GeneratedImage: Identifiable {
    let id: UUID
    let mimeType: String
    let base64Data: String?
    let remoteURL: URL?

    init(id: UUID = UUID(), mimeType: String, base64Data: String? = nil, remoteURL: URL? = nil) {
        self.id = id
        self.mimeType = mimeType
        self.base64Data = base64Data
        self.remoteURL = remoteURL
    }
}

enum GeneratedMediaKind: String, Codable {
    case image
    case audio
    case video
    case pdf
    case text
    case json
    case csv
    case file
}

struct GeneratedMedia: Identifiable, Codable {
    let id: UUID
    let kind: GeneratedMediaKind
    let mimeType: String
    let base64Data: String?
    let remoteURL: URL?

    init(
        id: UUID = UUID(),
        kind: GeneratedMediaKind,
        mimeType: String,
        base64Data: String? = nil,
        remoteURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.base64Data = base64Data
        self.remoteURL = remoteURL
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    let text: String
    let attachments: [AttachmentSummary]
    let generatedMedia: [GeneratedMedia]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        attachments: [AttachmentSummary],
        generatedMedia: [GeneratedMedia] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.generatedMedia = generatedMedia
    }
}

extension ChatMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case attachments
        case generatedMedia
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        attachments = try container.decode([AttachmentSummary].self, forKey: .attachments)
        generatedMedia = try container.decodeIfPresent([GeneratedMedia].self, forKey: .generatedMedia) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(generatedMedia, forKey: .generatedMedia)
    }
}

struct SavedConversation: Identifiable, Codable {
    var id: UUID
    var title: String
    var updatedAt: Date
    var modelID: String
    var messages: [ChatMessage]

    var searchBlob: String {
        let body = messages.map(\.text).joined(separator: "\n")
        return "\(title)\n\(body)"
    }
}

struct ModelReply {
    let text: String
    let generatedMedia: [GeneratedMedia]
}
