import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = PlaygroundViewModel()
    @State private var prompt = ""
    @State private var isKeyHidden = true
    @State private var historySearch = ""
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
            .navigationTitle("AI Playground")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset Chat") {
                        viewModel.clearMessages()
                    }
                }
            }
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
#endif
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("New Chat") {
                    viewModel.startNewChat()
                }
                .buttonStyle(.borderedProminent)

                Button("Delete") {
                    viewModel.deleteSelectedConversation()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedConversationID == nil)

                Spacer()
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
                    }
                }
                .buttonStyle(.plain)
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
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .listRowBackground(viewModel.selectedConversationID == conversation.id ? Color.accentColor.opacity(0.14) : Color.clear)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var configurationSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if isKeyHidden {
                        SecureField("Gemini API Key", text: $viewModel.apiKey)
                    } else {
                        TextField("Gemini API Key", text: $viewModel.apiKey)
                    }
                    Button(isKeyHidden ? "Show" : "Hide") {
                        isKeyHidden.toggle()
                    }
                }

                Picker("Preset", selection: $viewModel.selectedPreset) {
                    ForEach(ModelPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedPreset) { _, newValue in
                    viewModel.applyPreset(newValue)
                }

                HStack {
                    TextField("Model ID", text: $viewModel.modelID)
                    Button("Load Models") {
                        Task {
                            await viewModel.refreshModels()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading || viewModel.apiKey.isEmpty)
                }

                if !viewModel.availableModels.isEmpty {
                    Picker("Available Models", selection: $viewModel.modelID) {
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
                        HStack {
                            ProgressView()
                            Text("Thinking...")
                                .foregroundStyle(.secondary)
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
            .textSelection(.enabled)
        }
    }

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
                .frame(minHeight: 90, maxHeight: 150)
                .focused($inputFocused)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }

            HStack {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                .disabled(viewModel.isLoading || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty))
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

            if !message.generatedImages.isEmpty {
                ForEach(message.generatedImages) { image in
                    AssistantImageView(image: image)
                        .frame(maxWidth: 360, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
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
}
