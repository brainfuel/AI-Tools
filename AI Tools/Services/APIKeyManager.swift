import Foundation

/// Manages API keys across all providers: in-memory cache and debounced Keychain persistence.
/// Both view models share this concern — extracting it here eliminates duplication and
/// makes each VM's Keychain behaviour independently testable.
@MainActor
final class APIKeyManager {
    private let keychainStore: KeychainStore
    private(set) var keysByProvider: [AIProvider: String] = [:]
    private var pendingTasks: [AIProvider: Task<Void, Never>] = [:]

    /// Called on a Keychain write failure so the owning VM can surface an error message.
    var onPersistError: ((String) -> Void)?

    init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    deinit {
        pendingTasks.values.forEach { $0.cancel() }
    }

    func loadFromSecureStorage() {
        for provider in AIProvider.allCases {
            let stored = try? keychainStore.string(for: keychainAccount(for: provider))
            keysByProvider[provider] = stored ?? ""
        }
    }

    func key(for provider: AIProvider) -> String {
        keysByProvider[provider] ?? ""
    }

    func hasKey(for provider: AIProvider) -> Bool {
        !(keysByProvider[provider] ?? "").isEmpty
    }

    func updateKey(_ value: String, for provider: AIProvider) {
        keysByProvider[provider] = value
        queuePersist(value, for: provider)
    }

    // MARK: - Private

    private func queuePersist(_ value: String, for provider: AIProvider) {
        pendingTasks[provider]?.cancel()
        pendingTasks[provider] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistKey(value, for: provider)
            self.pendingTasks[provider] = nil
        }
    }

    private func persistKey(_ value: String, for provider: AIProvider) {
        do {
            if value.isEmpty {
                try keychainStore.removeValue(for: keychainAccount(for: provider))
            } else {
                try keychainStore.setString(value, for: keychainAccount(for: provider))
            }
        } catch {
            onPersistError?("Failed to persist \(provider.displayName) API key to Keychain: \(error.localizedDescription)")
        }
    }

    private func keychainAccount(for provider: AIProvider) -> String {
        "api-key.\(provider.rawValue)"
    }
}
