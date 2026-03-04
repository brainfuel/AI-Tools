import SwiftUI
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case single
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: return "Single"
        case .compare: return "Compare"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = PlaygroundViewModel()
    @StateObject private var compareViewModel = CompareViewModel()
    @State private var workspaceMode: WorkspaceMode = .single
    @State private var prompt = ""
    @State private var comparePrompt = ""
    @State private var isKeyHidden = true
    @State private var historySearch = ""
    @State private var showingUsageStats = false
    @State private var showingFileImporter = false
    @State private var showingCompareFileImporter = false
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var comparePendingAttachments: [PendingAttachment] = []
    @FocusState private var inputFocused: Bool
    @FocusState private var compareInputFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
            .navigationTitle("AI Tools")
            .toolbar {
                if workspaceMode == .single {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingUsageStats = true
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }
                        .help("Usage Stats")
                    }
                }
            }
            .sheet(isPresented: $showingUsageStats) {
                UsageStatsSheet(
                    modelID: viewModel.modelID,
                    sessionInputTokens: viewModel.sessionInputTokens,
                    sessionOutputTokens: viewModel.sessionOutputTokens,
                    windows: viewModel.usageTimeWindows
                )
            }
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
#endif
        .task {
            await viewModel.loadOnLaunchIfNeeded()
            await compareViewModel.loadOnLaunchIfNeeded()
        }
        .onChange(of: workspaceMode) { _, mode in
            guard mode == .compare else { return }
            compareViewModel.reloadFromStorage()
        }
    }

    private var detailContent: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if workspaceMode == .single {
                configurationSection
                Divider()
                messagesSection
                composerSection
            } else {
                compareModeSection
            }
        }
        .padding()
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    viewModel.startNewChat()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Chat")
                .buttonStyle(.borderedProminent)


                Spacer()
                
                Button(role: .destructive) {
                    viewModel.deleteSelectedConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Chat")
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedConversationID == nil)

             
            }

            TextField("Search History", text: $historySearch)
                .textFieldStyle(.roundedBorder)

            List {
                Button {
                    viewModel.selectConversation(nil)
                } label: {
                    HStack {
                        Image(systemName: "plus.bubble")
                        Text("Current Chat")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .listRowBackground(viewModel.selectedConversationID == nil ? Color.accentColor.opacity(0.14) : Color.clear)

                ForEach(viewModel.filteredConversations(query: historySearch)) { conversation in
                    Button {
                        viewModel.selectConversation(conversation.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title)
                                .lineLimit(1)
                            Text(conversation.updatedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .listRowBackground(viewModel.selectedConversationID == conversation.id ? Color.accentColor.opacity(0.14) : Color.clear)
                }
            }
            .listStyle(.sidebar)
            .animation(.easeInOut(duration: 0.2), value: viewModel.savedConversations.map(\.id))
        }
    }

    private var configurationSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Provider", selection: $viewModel.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedProvider) { _, newValue in
                    Task {
                        await viewModel.selectProvider(newValue)
                    }
                }

                HStack {
                    if isKeyHidden {
                        SecureField(viewModel.providerAPIKeyPlaceholder, text: apiKeyBinding)
                    } else {
                        TextField(viewModel.providerAPIKeyPlaceholder, text: apiKeyBinding)
                    }
                    Button(isKeyHidden ? "Show" : "Hide") {
                        isKeyHidden.toggle()
                    }
                }

                HStack {
                    Button("Load Models") {
                        Task {
                            await viewModel.refreshModels()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading || viewModel.currentAPIKey.isEmpty || !viewModel.canLoadModels)

                    if viewModel.availableModels.isEmpty {
                        Text(viewModel.currentAPIKey.isEmpty ? "Enter API key to load models" : "Load models to choose one")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.availableModels.isEmpty {
                    Picker("Available Models", selection: modelSelectionBinding) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("System Instructions (optional)", text: $viewModel.systemInstruction, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }

    private var messagesSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        if viewModel.streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 16, height: 16)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                            }
                            .id("loading-indicator")
                        } else {
                            streamingBubble
                                .id("streaming-bubble")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                proxy.scrollTo("streaming-bubble", anchor: .bottom)
            }
            .textSelection(.enabled)
        }
    }

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MessageRole.assistant.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            MarkdownText(viewModel.streamingText)
                .padding(10)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private extension ContentView {
    var compareModeSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    compareProviderColumn(provider)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            compareComposerSection
        }
    }

    func compareProviderColumn(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                if compareViewModel.hasAPIKey(for: provider) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("API key is configured")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Missing API key")
                }
            }

            HStack(spacing: 8) {
                if compareViewModel.modelsForPicker(for: provider).isEmpty {
                    Text("No models cached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: compareModelBinding(for: provider)) {
                        ForEach(compareViewModel.modelsForPicker(for: provider), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button("Load") {
                    Task {
                        await compareViewModel.refreshModels(for: provider)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(compareViewModel.isSending || !compareViewModel.hasAPIKey(for: provider))
            }

            if let message = compareViewModel.providerStatusMessage(provider),
               !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if compareViewModel.runs.isEmpty {
                        Text("No compare runs yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(compareViewModel.runs) { run in
                            compareRunCard(run: run, provider: provider)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func compareRunCard(run: CompareRun, provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.createdAt, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(run.prompt)
                .font(.subheadline)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if !run.attachments.isEmpty {
                ForEach(run.attachments) { attachment in
                    MessageAttachmentView(attachment: attachment)
                }
            }

            if let result = run.results[provider] {
                switch result.state {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                        Text("Thinking...")
                            .foregroundStyle(.secondary)
                    }
                    if !result.text.isEmpty {
                        MarkdownText(result.text)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                case .success:
                    if !result.text.isEmpty {
                        MarkdownText(result.text)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if !result.generatedMedia.isEmpty {
                        ForEach(result.generatedMedia) { media in
                            AssistantMediaView(media: media)
                                .frame(maxWidth: 360)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if result.inputTokens > 0 || result.outputTokens > 0 {
                        TokenUsageRow(
                            modelID: result.modelID,
                            inputTokens: result.inputTokens,
                            outputTokens: result.outputTokens
                        )
                    }
                case .failed:
                    if let error = result.errorMessage {
                        Button {
                            copyToClipboard(error)
                        } label: {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy error")
                    }
                case .skipped:
                    Text(result.errorMessage ?? "Skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var compareComposerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !comparePendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(comparePendingAttachments) { attachment in
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    AttachmentPreview(attachment: attachment)
                                        .frame(width: 120, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button {
                                        comparePendingAttachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(attachment.name)
                                    .lineLimit(1)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            TextEditor(text: $comparePrompt)
                .focused($compareInputFocused)
                .padding(8)
                .frame(minHeight: 90, maxHeight: 150)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }

            HStack {
                if let errorMessage = compareViewModel.errorMessage {
                    Button {
                        copyToClipboard(errorMessage)
                    } label: {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy error")
                } else {
                    Text(compareViewModel.composerStatusLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Attach") {
                    showingCompareFileImporter = true
                }
                .buttonStyle(.bordered)
                .disabled(compareViewModel.isSending)

                Button("Send All") {
                    sendCompareMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    compareViewModel.isSending ||
                    (comparePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && comparePendingAttachments.isEmpty)
                )
            }
        }
        .fileImporter(
            isPresented: $showingCompareFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleCompareImportResult(result)
        }
    }

    func compareModelBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { compareViewModel.selectedModel(for: provider) },
            set: { compareViewModel.selectModel($0, for: provider) }
        )
    }

    func sendCompareMessage() {
        let text = comparePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !comparePendingAttachments.isEmpty else { return }
        let attachments = comparePendingAttachments
        comparePrompt = ""
        comparePendingAttachments = []
        compareInputFocused = false
        Task {
            await compareViewModel.sendCompare(text: text, attachments: attachments)
        }
    }

    func handleCompareImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            compareViewModel.errorMessage = "Attachment import failed: \(error.localizedDescription)"
        case .success(let urls):
            for url in urls {
                do {
                    let attachment = try PendingAttachment.fromFileURL(url)
                    comparePendingAttachments.append(attachment)
                } catch {
                    compareViewModel.errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Token usage views

private struct TokenUsageRow: View {
    let modelID: String
    let inputTokens: Int
    let outputTokens: Int

    var body: some View {
        HStack(spacing: 10) {
            Label("\(inputTokens.formatted()) in", systemImage: "arrow.up")
            Label("\(outputTokens.formatted()) out", systemImage: "arrow.down")
            if let cost = TokenCostCalculator.cost(for: modelID, inputTokens: inputTokens, outputTokens: outputTokens) {
                Text(costString(cost))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 {
            return String(format: "~$%.6f", cost)
        } else if cost < 0.01 {
            return String(format: "~$%.4f", cost)
        } else {
            return String(format: "~$%.3f", cost)
        }
    }
}

private struct SessionTokenSummary: View {
    let modelID: String
    let inputTokens: Int
    let outputTokens: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .imageScale(.small)
            Text("Session: \(inputTokens.formatted()) in · \(outputTokens.formatted()) out")
            if let cost = TokenCostCalculator.cost(for: modelID, inputTokens: inputTokens, outputTokens: outputTokens) {
                Text(costString(cost))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 {
            return String(format: "·~$%.6f", cost)
        } else if cost < 0.01 {
            return String(format: "·~$%.4f", cost)
        } else {
            return String(format: "·~$%.3f", cost)
        }
    }
}

private struct UsageTimeWindowSummaryView: View {
    let windows: [UsageTimeWindowSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Usage (estimate)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(windows) { window in
                Text(
                    "\(window.label): \(window.inputTokens.formatted()) in · \(window.outputTokens.formatted()) out · \(costString(window.estimatedCost))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func costString(_ cost: Double) -> String {
        if cost < 0.0001 {
            return String(format: "~$%.6f", cost)
        } else if cost < 0.01 {
            return String(format: "~$%.4f", cost)
        } else {
            return String(format: "~$%.3f", cost)
        }
    }
}

private struct UsageStatsSheet: View {
    let modelID: String
    let sessionInputTokens: Int
    let sessionOutputTokens: Int
    let windows: [UsageTimeWindowSummary]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Usage Stats", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            GroupBox("Current Chat") {
                if sessionInputTokens > 0 || sessionOutputTokens > 0 {
                    SessionTokenSummary(
                        modelID: modelID,
                        inputTokens: sessionInputTokens,
                        outputTokens: sessionOutputTokens
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No token usage yet in this chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Rolling Totals") {
                UsageTimeWindowSummaryView(windows: windows)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 250)
    }
}

// Needed because the extension closing brace was consumed above
private extension ContentView {

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    AttachmentPreview(attachment: attachment)
                                        .frame(width: 120, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button {
                                        pendingAttachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Text(attachment.name)
                                    .lineLimit(1)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            TextEditor(text: $prompt)
                .focused($inputFocused)
                .padding(8)
                .frame(minHeight: 90, maxHeight: 150)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }

            HStack {
                if let errorMessage = viewModel.errorMessage {
                    Button {
                        copyToClipboard(errorMessage)
                    } label: {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy error")
                } else {
                    Text("Ready")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Attach") {
                    showingFileImporter = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)

                Button("Send") {
                    sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isLoading ||
                    !viewModel.canSendRequests ||
                    (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                )
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !message.text.isEmpty {
                Group {
                    if message.role == .assistant {
                        MarkdownText(message.text)
                    } else {
                        Text(message.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if !message.attachments.isEmpty {
                ForEach(message.attachments) { attachment in
                    MessageAttachmentView(attachment: attachment)
                }
            }

            if !message.generatedMedia.isEmpty {
                ForEach(message.generatedMedia) { media in
                    AssistantMediaView(media: media)
                        .frame(maxWidth: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if message.role == .assistant,
               message.inputTokens > 0 || message.outputTokens > 0 {
                TokenUsageRow(
                    modelID: message.modelID ?? "",
                    inputTokens: message.inputTokens,
                    outputTokens: message.outputTokens
                )
            }
        }
    }

    private func sendMessage() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        let attachments = pendingAttachments
        prompt = ""
        pendingAttachments = []
        inputFocused = false
        Task {
            await viewModel.send(text: text, attachments: attachments)
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { viewModel.currentAPIKey },
            set: { viewModel.updateCurrentAPIKey($0) }
        )
    }

    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: { viewModel.modelID },
            set: { viewModel.selectModel($0) }
        )
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            viewModel.errorMessage = "Attachment import failed: \(error.localizedDescription)"
        case .success(let urls):
            for url in urls {
                do {
                    let attachment = try PendingAttachment.fromFileURL(url)
                    pendingAttachments.append(attachment)
                } catch {
                    viewModel.errorMessage = "Failed to load \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    private func copyToClipboard(_ value: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = value
#endif
    }
}
