import Foundation
import SwiftUI

/// Manages model list caching and per-provider selection, backed by AppStorage.
///
/// Both PlaygroundViewModel and CompareViewModel need this logic — centralising it
/// here removes ~100 lines of duplication and gives each VM a single call-site
/// for cache reads/writes.
@MainActor
final class ModelService {
    @AppStorage("gemini_model_id")           private var geminiModelID    = "gemini-2.5-flash"
    @AppStorage("openai_model_id")           private var openAIModelID    = "gpt-4.1-mini"
    @AppStorage("anthropic_model_id")        private var anthropicModelID = "claude-3-5-sonnet-latest"
    @AppStorage("grok_model_id")             private var grokModelID      = "grok-3-mini"
    @AppStorage("gemini_models_cache_v1")    private var geminiCache      = ""
    @AppStorage("openai_models_cache_v1")    private var openAICache      = ""
    @AppStorage("anthropic_models_cache_v1") private var anthropicCache   = ""
    @AppStorage("grok_models_cache_v1")      private var grokCache        = ""

    private(set) var availableModelsByProvider: [AIProvider: [String]] = [:]

    init() {
        loadCachesFromStorage()
    }

    // MARK: - Selection

    func selectedModelID(for provider: AIProvider) -> String {
        switch provider {
        case .gemini:    return geminiModelID
        case .chatGPT:   return openAIModelID
        case .anthropic: return anthropicModelID
        case .grok:      return grokModelID
        }
    }

    func selectModel(_ modelID: String, for provider: AIProvider) {
        switch provider {
        case .gemini:    geminiModelID    = modelID
        case .chatGPT:   openAIModelID    = modelID
        case .anthropic: anthropicModelID = modelID
        case .grok:      grokModelID      = modelID
        }
    }

    // MARK: - Cache reads

    /// Returns the cached model list for a provider, inserting `selected` at the front
    /// if it is non-empty and not already present (e.g. a conversation's model).
    func availableModels(for provider: AIProvider, including selected: String? = nil) -> [String] {
        var models = availableModelsByProvider[provider] ?? []
        guard !models.isEmpty else { return models }
        if let selected, !selected.isEmpty, !models.contains(selected) {
            models.insert(selected, at: 0)
        }
        return models
    }

    // MARK: - Cache writes

    func loadCachesFromStorage() {
        availableModelsByProvider[.gemini]    = decode(geminiCache)
        availableModelsByProvider[.chatGPT]   = decode(openAICache)
        availableModelsByProvider[.anthropic] = decode(anthropicCache)
        availableModelsByProvider[.grok]      = decode(grokCache)
    }

    /// Deduplicates and stores a fresh model list. If the current selection is no longer
    /// in the list, resets it to the first entry. Returns the stored list.
    @discardableResult
    func updateCache(_ models: [String], for provider: AIProvider) -> [String] {
        var seen = Set<String>()
        let unique = models.filter { seen.insert($0).inserted }
        availableModelsByProvider[provider] = unique
        persistCache(unique, for: provider)
        if !unique.isEmpty, !unique.contains(selectedModelID(for: provider)) {
            selectModel(unique[0], for: provider)
        }
        return unique
    }

    // MARK: - Private

    private func persistCache(_ models: [String], for provider: AIProvider) {
        let encoded = encode(models)
        switch provider {
        case .gemini:    geminiCache    = encoded
        case .chatGPT:   openAICache    = encoded
        case .anthropic: anthropicCache = encoded
        case .grok:      grokCache      = encoded
        }
    }

    private func decode(_ raw: String) -> [String] {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }

    private func encode(_ models: [String]) -> String {
        guard let data = try? JSONEncoder().encode(models),
              let raw = String(data: data, encoding: .utf8) else { return "" }
        return raw
    }
}
