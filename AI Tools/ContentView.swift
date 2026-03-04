import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = PlaygroundViewModel()
    @State private var prompt = ""
    @State private var isKeyHidden = true
    @State private var historySearch = ""
    @State private var showingUsageStats = false
    @State private var showingFileImporter = false
    @State private var pendingAttachments: [PendingAttachment] = []
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 12) {
                configurationSection
                Divider()
                messagesSection
                composerSection
            }
            .padding()
            .navigationTitle("AI Tools")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingUsageStats = true
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .help("Usage Stats")
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
        }
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
                    Text("Attachment: \(attachment.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
