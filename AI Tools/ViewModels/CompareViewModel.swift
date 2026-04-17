import Foundation
import SwiftUI
import Combine

@MainActor
final class CompareViewModel: ObservableObject {
    @AppStorage("compare_conversations_v1") private var compareConversationsStore = ""

    @Published var savedConversations: [CompareConversation] = []
    @Published var selectedConversationID: UUID?
    @Published var runs: [CompareRun] = []
    @Published var errorMessage: String?
    @Published private(set) var isSending = false
    @Published var pendingAttachments: [PendingAttachment] = []

    // @Published mirrors so SwiftUI redraws pickers/status icons when services update.
    @Published private var selectedModelsByProvider: [AIProvider: String] = [:]
    @Published private var availableModelsByProvider: [AIProvider: [String]] = [:]
    @Published private var apiKeysByProvider: [AIProvider: String] = [:]
    @Published private var providerStatusByProvider: [AIProvider: String] = [:]

    private let apiKeyManager: APIKeyManager
    private let modelService: ModelService
    private let serviceFactory: (AIProvider, String) -> GeminiServicing
    private var didAutoLoadModels = false

    init(
        apiKeyManager: APIKeyManager? = nil,
        modelService: ModelService? = nil,
        serviceFactory: @escaping (AIProvider, String) -> GeminiServicing = { provider, key in
            switch provider {
            case .gemini:    return GeminiClient(apiKey: key)
            case .chatGPT:   return OpenAIClient(apiKey: key)
            case .anthropic: return AnthropicClient(apiKey: key)
            case .grok:      return GrokClient(apiKey: key)
            }
        }
    ) {
        let resolvedAPIKeyManager = apiKeyManager ?? APIKeyManager()
        let resolvedModelService = modelService ?? ModelService()

        self.apiKeyManager = resolvedAPIKeyManager
        self.modelService = resolvedModelService
        self.serviceFactory = serviceFactory
        loadSavedConversations()
        reloadFromStorage(includeSecureStorage: true)
    }

    // MARK: - Public interface

    var composerStatusLabel: String {
        let ready = readyProviders
        if ready.isEmpty { return "No providers ready. Add keys in Single mode." }
        return "Ready: \(ready.map(\.displayName).joined(separator: ", "))"
    }

    var readyProviders: [AIProvider] {
        AIProvider.allCases.filter { hasAPIKey(for: $0) && !selectedModel(for: $0).isEmpty }
    }

    var runsChronological: [CompareRun] {
        runs.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.createdAt < rhs.createdAt
        }
    }

    func loadOnLaunchIfNeeded() async {
        guard !didAutoLoadModels else { return }
        didAutoLoadModels = true
        reloadFromStorage()
        for provider in AIProvider.allCases where hasAPIKey(for: provider) {
            await fetchModels(for: provider, reportErrors: false)
        }
    }

    func reloadFromStorage(includeSecureStorage: Bool = false) {
        if includeSecureStorage {
            apiKeyManager.loadFromSecureStorage()
            syncAPIKeys()
        }
        modelService.loadCachesFromStorage()
        syncModelMirrors()
        if let selectedConversationID {
            if let conversation = savedConversations.first(where: { $0.id == selectedConversationID }) {
                runs = conversation.runs
            } else {
                self.selectedConversationID = nil
            }
        }
    }

    func startNewThread() {
        selectedConversationID = nil
        runs.removeAll()
        errorMessage = nil
    }

    func selectConversation(_ id: UUID?) {
        selectedConversationID = id
        guard let id, let conversation = savedConversations.first(where: { $0.id == id }) else {
            runs.removeAll()
            errorMessage = nil
            return
        }
        runs = conversation.runs
        errorMessage = nil
    }

    func deleteSelectedConversation() {
        guard let id = selectedConversationID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            savedConversations.removeAll { $0.id == id }
            selectedConversationID = nil
            runs.removeAll()
        }
        persistSavedConversations()
    }

    func filteredConversations(query: String) -> [CompareConversation] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return savedConversations }
        return savedConversations.filter { $0.searchBlob.localizedCaseInsensitiveContains(needle) }
    }

    func selectedModel(for provider: AIProvider) -> String {
        selectedModelsByProvider[provider] ?? ""
    }

    func selectModel(_ model: String, for provider: AIProvider) {
        selectedModelsByProvider[provider] = model
        modelService.selectModel(model, for: provider)
    }

    func modelsForPicker(for provider: AIProvider) -> [String] {
        availableModelsByProvider[provider] ?? []
    }

    func providerStatusMessage(_ provider: AIProvider) -> String? {
        if let status = providerStatusByProvider[provider], !status.isEmpty { return status }
        if !hasAPIKey(for: provider) { return "Set \(provider.displayName) API key in Single mode." }
        return nil
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !(apiKeysByProvider[provider] ?? "").isEmpty
    }

    func canContinueInSingle(for provider: AIProvider) -> Bool {
        let selected = selectedModel(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return false }
        return !singleChatMessages(for: provider).isEmpty
    }

    func makeSingleConversation(for provider: AIProvider) -> SavedConversation? {
        let messages = singleChatMessages(for: provider)
        guard !messages.isEmpty else { return nil }

        let selected = selectedModel(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackModel = runs
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { run -> String? in
                let model = run.results[provider]?.modelID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return model.isEmpty ? nil : model
            }
            .last
        let modelID = !selected.isEmpty ? selected : (fallbackModel ?? "")
        guard !modelID.isEmpty else { return nil }

        let titleSeed = messages.first(where: { $0.role == .user })?.text ?? "\(provider.displayName) Thread"
        return SavedConversation(
            id: UUID(), provider: provider,
            title: makeTitle(from: titleSeed),
            updatedAt: Date(), modelID: modelID, messages: messages
        )
    }

    func refreshModels(for provider: AIProvider) async {
        await fetchModels(for: provider, reportErrors: true)
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func addAttachments(fromResult result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Attachment import failed: \(error.localizedDescription)"
        case .success(let urls):
            for url in urls {
                do {
                    let attachment = try PendingAttachment.fromFileURL(url)
                    pendingAttachments.append(attachment)
                } catch {
                    errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    func sendCompare(text: String) async {
        errorMessage = nil
        let attachments = pendingAttachments
        pendingAttachments = []

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty || !attachments.isEmpty else { return }

        let providers = readyProviders
        guard !providers.isEmpty else {
            errorMessage = "No provider is ready. Add at least one API key in Single mode."
            return
        }

        let prompt = normalizedText.isEmpty ? "(Attachment only)" : normalizedText
        let summaries = attachments.map {
            AttachmentSummary(name: $0.name, mimeType: $0.mimeType,
                              previewBase64Data: $0.previewJPEGData?.base64EncodedString())
        }

        var initialResults: [AIProvider: CompareProviderResult] = [:]
        for provider in AIProvider.allCases {
            if providers.contains(provider) {
                initialResults[provider] = CompareProviderResult(
                    state: .loading, modelID: selectedModel(for: provider),
                    text: "", generatedMedia: [], inputTokens: 0, outputTokens: 0, errorMessage: nil
                )
            } else {
                let reason = hasAPIKey(for: provider) ? "No model selected." : "Missing API key."
                initialResults[provider] = CompareProviderResult(
                    state: .skipped, modelID: selectedModel(for: provider),
                    text: "", generatedMedia: [], inputTokens: 0, outputTokens: 0, errorMessage: reason
                )
            }
        }

        let run = CompareRun(id: UUID(), prompt: prompt, attachments: summaries,
                             createdAt: Date(), results: initialResults)
        runs.insert(run, at: 0)
        upsertCurrentConversation()

        let runID = run.id
        isSending = true
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    await self?.executeRun(for: provider, runID: runID, prompt: prompt, attachments: attachments)
                }
            }
        }
        isSending = false
        upsertCurrentConversation()
    }

    // MARK: - Private: model fetching

    private func fetchModels(for provider: AIProvider, reportErrors: Bool) async {
        let apiKey = apiKeysByProvider[provider] ?? ""
        guard !apiKey.isEmpty else {
            if reportErrors { providerStatusByProvider[provider] = "Missing API key." }
            return
        }
        do {
            let models = try await serviceFactory(provider, apiKey).listGenerateContentModels()
            let unique = modelService.updateCache(models, for: provider)
            availableModelsByProvider[provider] = modelsForPickerFromService(for: provider)
            selectedModelsByProvider[provider] = modelService.selectedModelID(for: provider)
            providerStatusByProvider[provider] = unique.isEmpty ? "No models returned." : "Loaded \(unique.count) model(s)."
        } catch {
            if reportErrors { providerStatusByProvider[provider] = error.localizedDescription }
        }
    }

    private func executeRun(
        for provider: AIProvider,
        runID: UUID,
        prompt: String,
        attachments: [PendingAttachment]
    ) async {
        let apiKey = apiKeysByProvider[provider] ?? ""
        let model = selectedModel(for: provider)

        var chunks: [String] = []
        var accumulatedMedia: [GeneratedMedia] = []
        var inputTokens = 0
        var outputTokens = 0

        do {
            let priorRunsOldestFirst = runs.filter { $0.id != runID }.reversed()
            var messages: [ChatMessage] = []
            for priorRun in priorRunsOldestFirst {
                messages.append(ChatMessage(role: .user, text: priorRun.prompt, attachments: priorRun.attachments))
                if let result = priorRun.results[provider], result.state == .success, !result.text.isEmpty {
                    messages.append(ChatMessage(role: .assistant, text: result.text, attachments: []))
                }
            }
            messages.append(ChatMessage(
                role: .user, text: prompt,
                attachments: attachments.map {
                    AttachmentSummary(name: $0.name, mimeType: $0.mimeType,
                                     previewBase64Data: $0.previewJPEGData?.base64EncodedString())
                }
            ))

            let stream = serviceFactory(provider, apiKey).generateReplyStream(
                modelID: model, systemInstruction: "",
                messages: messages, latestUserAttachments: attachments
            )
            for try await chunk in stream {
                chunks.append(chunk.text)
                accumulatedMedia += chunk.generatedMedia
                if chunk.inputTokens > 0 { inputTokens = chunk.inputTokens }
                if chunk.outputTokens > 0 { outputTokens = chunk.outputTokens }
                updateRun(runID: runID, provider: provider, result: CompareProviderResult(
                    state: .loading, modelID: model, text: chunks.joined(),
                    generatedMedia: accumulatedMedia, inputTokens: inputTokens,
                    outputTokens: outputTokens, errorMessage: nil
                ))
            }
            updateRun(runID: runID, provider: provider, result: CompareProviderResult(
                state: .success, modelID: model,
                text: chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines),
                generatedMedia: accumulatedMedia, inputTokens: inputTokens,
                outputTokens: outputTokens, errorMessage: nil
            ))
        } catch {
            updateRun(runID: runID, provider: provider, result: CompareProviderResult(
                state: .failed, modelID: model, text: "", generatedMedia: [],
                inputTokens: 0, outputTokens: 0, errorMessage: error.localizedDescription
            ))
        }
    }

    private func updateRun(runID: UUID, provider: AIProvider, result: CompareProviderResult) {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
        var run = runs[index]
        run.results[provider] = result
        runs[index] = run
    }

    // MARK: - Private: service mirror sync

    private func syncAPIKeys() {
        for provider in AIProvider.allCases {
            apiKeysByProvider[provider] = apiKeyManager.key(for: provider)
        }
    }

    private func syncModelMirrors() {
        for provider in AIProvider.allCases {
            selectedModelsByProvider[provider]  = modelService.selectedModelID(for: provider)
            availableModelsByProvider[provider] = modelsForPickerFromService(for: provider)
        }
    }

    private func modelsForPickerFromService(for provider: AIProvider) -> [String] {
        let cached   = modelService.availableModelsByProvider[provider] ?? []
        let selected = modelService.selectedModelID(for: provider)
        guard !selected.isEmpty else { return cached }
        return cached.contains(selected) ? cached : [selected] + cached
    }

    // MARK: - Private: conversation helpers

    private func singleChatMessages(for provider: AIProvider) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        for run in runs.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let result = run.results[provider], result.state != .skipped else { continue }
            messages.append(ChatMessage(role: .user, text: run.prompt,
                                        createdAt: run.createdAt, attachments: run.attachments))
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPayload = !text.isEmpty || !result.generatedMedia.isEmpty
                || result.inputTokens > 0 || result.outputTokens > 0
            guard hasPayload else { continue }
            messages.append(ChatMessage(
                role: .assistant, text: text,
                createdAt: run.createdAt.addingTimeInterval(0.001),
                attachments: [], generatedMedia: result.generatedMedia,
                inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                modelID: result.modelID.isEmpty ? nil : result.modelID
            ))
        }
        return messages
    }

    private func upsertCurrentConversation() {
        guard !runs.isEmpty else { return }
        let title = makeTitle(from: runs.first?.prompt ?? "Compare")
        let now   = Date()
        if let id = selectedConversationID,
           let index = savedConversations.firstIndex(where: { $0.id == id }) {
            savedConversations[index].runs      = runs
            savedConversations[index].title     = title
            savedConversations[index].updatedAt = now
        } else {
            let id = UUID()
            savedConversations.insert(
                CompareConversation(id: id, title: title, updatedAt: now, runs: runs), at: 0
            )
            selectedConversationID = id
        }
        savedConversations.sort { $0.updatedAt > $1.updatedAt }
        persistSavedConversations()
    }

    private func makeTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Compare Thread" }
        let compact = trimmed.replacingOccurrences(of: "\n", with: " ")
        return compact.count > 44 ? String(compact.prefix(44)) + "..." : compact
    }

    private func loadSavedConversations() {
        guard !compareConversationsStore.isEmpty,
              let data = compareConversationsStore.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CompareConversation].self, from: data) else {
            savedConversations = []
            return
        }
        savedConversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persistSavedConversations() {
        guard let data = try? JSONEncoder().encode(savedConversations),
              let encoded = String(data: data, encoding: .utf8) else { return }
        compareConversationsStore = encoded
    }
}
