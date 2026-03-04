import XCTest
@testable import AI_Tools

@MainActor
final class PlaygroundViewModelTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let storageKeys = [
        "ai_provider",
        "gemini_model_id",
        "openai_model_id",
        "anthropic_model_id",
        "gemini_models_cache_v1",
        "openai_models_cache_v1",
        "anthropic_models_cache_v1",
        "gemini_system_instruction"
    ]

    private var previousDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        previousDefaults = [:]

        for key in storageKeys {
            if let value = defaults.object(forKey: key) {
                previousDefaults[key] = value
            }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in storageKeys {
            defaults.removeObject(forKey: key)
        }

        for (key, value) in previousDefaults {
            defaults.set(value, forKey: key)
        }
        previousDefaults = [:]
        super.tearDown()
    }

    func testSelectingConversationUsesCachedModelsImmediatelyWithoutFetch() async {
        let recorder = ModelListRecorder()
        let modelMap: [AIProvider: [String]] = [
            .chatGPT: ["gpt-4.1-mini", "o3-mini"]
        ]

        defaults.set(encode(["gpt-4.1-mini", "o3-mini"]), forKey: "openai_models_cache_v1")

        let viewModel = makeViewModel(modelMap: modelMap, recorder: recorder)
        let conversation = SavedConversation(
            id: UUID(),
            provider: .chatGPT,
            title: "OpenAI chat",
            updatedAt: Date(),
            modelID: "gpt-4.1-mini",
            messages: [
                ChatMessage(role: .user, text: "hello", attachments: [])
            ]
        )

        viewModel.savedConversations = [conversation]
        viewModel.selectConversation(conversation.id)

        XCTAssertEqual(viewModel.selectedProvider, .chatGPT)
        XCTAssertEqual(viewModel.modelID, "gpt-4.1-mini")
        XCTAssertEqual(viewModel.availableModels, ["gpt-4.1-mini", "o3-mini"])

        let calls = await recorder.snapshot()
        XCTAssertTrue(calls.isEmpty)
    }

    func testSelectingProviderUsesCachedModelsWithoutNetworkFetch() async {
        let recorder = ModelListRecorder()
        let modelMap: [AIProvider: [String]] = [
            .anthropic: ["claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest"]
        ]

        defaults.set(encode(["claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest"]), forKey: "anthropic_models_cache_v1")

        let viewModel = makeViewModel(modelMap: modelMap, recorder: recorder)
        await viewModel.selectProvider(.anthropic)

        XCTAssertEqual(viewModel.availableModels, ["claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest"])
        let calls = await recorder.snapshot()
        XCTAssertTrue(calls.isEmpty)
    }

    func testLoadOnLaunchPrefetchesForProvidersWithKeysAndOnlyOnce() async {
        let recorder = ModelListRecorder()
        let modelMap: [AIProvider: [String]] = [
            .gemini: ["gemini-2.5-flash", "gemini-2.5-pro"],
            .chatGPT: ["gpt-4.1-mini", "o3-mini"],
            .anthropic: ["claude-3-5-sonnet-latest"]
        ]

        let viewModel = makeViewModel(modelMap: modelMap, recorder: recorder)
        viewModel.updateCurrentAPIKey("gemini-key")
        await viewModel.selectProvider(.chatGPT)
        viewModel.updateCurrentAPIKey("openai-key")
        await viewModel.selectProvider(.gemini)

        await viewModel.loadOnLaunchIfNeeded()

        var calls = await recorder.snapshot()
        XCTAssertEqual(calls[.gemini], 1)
        XCTAssertEqual(calls[.chatGPT], 1)
        XCTAssertNil(calls[.anthropic])

        XCTAssertEqual(viewModel.availableModels, ["gemini-2.5-flash", "gemini-2.5-pro"])

        await viewModel.loadOnLaunchIfNeeded()
        calls = await recorder.snapshot()
        XCTAssertEqual(calls[.gemini], 1)
        XCTAssertEqual(calls[.chatGPT], 1)

        let geminiCached = decode(defaults.string(forKey: "gemini_models_cache_v1") ?? "")
        let openAICached = decode(defaults.string(forKey: "openai_models_cache_v1") ?? "")
        XCTAssertEqual(geminiCached, ["gemini-2.5-flash", "gemini-2.5-pro"])
        XCTAssertEqual(openAICached, ["gpt-4.1-mini", "o3-mini"])
    }

    private func makeViewModel(
        modelMap: [AIProvider: [String]],
        recorder: ModelListRecorder
    ) -> PlaygroundViewModel {
        let keychainService = "com.moosia.AI-ToolsTests.\(UUID().uuidString)"
        return PlaygroundViewModel(
            serviceFactory: { provider, _ in
                MockService(provider: provider, modelMap: modelMap, recorder: recorder)
            },
            keychainStore: KeychainStore(service: keychainService),
            conversationStoreFactory: { nil }
        )
    }

    private func encode(_ models: [String]) -> String {
        guard let data = try? JSONEncoder().encode(models),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }
}

private actor ModelListRecorder {
    private var calls: [AIProvider: Int] = [:]

    func record(provider: AIProvider) {
        calls[provider, default: 0] += 1
    }

    func snapshot() -> [AIProvider: Int] {
        calls
    }
}

private struct MockService: GeminiServicing {
    let provider: AIProvider
    let modelMap: [AIProvider: [String]]
    let recorder: ModelListRecorder

    func listGenerateContentModels() async throws -> [String] {
        await recorder.record(provider: provider)
        return modelMap[provider] ?? []
    }

    func generateReply(
        modelID: String,
        systemInstruction: String,
        messages: [ChatMessage],
        latestUserAttachments: [PendingAttachment]
    ) async throws -> ModelReply {
        ModelReply(text: "", generatedMedia: [])
    }
}
