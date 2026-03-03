# AI Tools

A SwiftUI AI playground app for chatting with multiple providers from one interface.

## Overview

AI Tools lets you:

- switch between Gemini, OpenAI, and Anthropic
- load available models from each provider
- keep local chat history with searchable conversations
- send prompts with optional file attachments
- view and save generated media (images, audio, video, PDF, text, JSON, CSV)

## Features

- Unified chat UI across providers
- Provider-specific API keys and model IDs saved per provider
- Conversation sidebar with new/delete/search
- Markdown rendering for assistant responses
- Attachment import with image preprocessing (center-crop to square, resize up to 1280x1280, JPEG encode)
- 18 MB attachment size limit per file
- Media output viewer with Save export flow

## Provider Support

| Provider | Chat | Model List | Attachments | Media Output |
|---|---|---|---|---|
| Gemini | Yes | Yes | Yes | Yes |
| OpenAI | Yes | Yes | Not sent yet | Image generation models supported |
| Anthropic | Yes | Yes | Not sent yet | Text only |

Notes:

- OpenAI image generation is used automatically when an image model ID is selected (for example `gpt-image-*` or `dall-e-*`).
- For OpenAI and Anthropic, attachments are currently acknowledged in-chat but not uploaded to those APIs yet.

## Requirements

- Xcode 17+
- Apple platform SDKs supported by your local Xcode install
- Valid API key(s) for any provider you want to use

The current project settings in `AI Tools.xcodeproj` target the latest SDK versions configured in the project file.

## Getting Started

1. Clone this repository.
2. Open [AI Tools.xcodeproj](AI%20Tools.xcodeproj) in Xcode.
3. Select the `AI Tools` scheme.
4. Choose a run destination (for example `My Mac`).
5. Build and run.

CLI build example:

```bash
xcodebuild -project "AI Tools.xcodeproj" -scheme "AI Tools" -configuration Debug build
```

## Usage

1. Select a provider in the **Connection** section.
2. Paste the provider API key.
3. (Optional) Click **Load Models** and choose a model.
4. Add system instructions if needed.
5. Type a prompt, optionally attach files, then click **Send**.
6. Use the chat history sidebar to reopen prior conversations.

## Data Storage

- API keys, selected models, system instruction, and saved conversations are stored locally using `@AppStorage` (UserDefaults).
- No server-side app backend is included in this project.

## Project Structure

- [AI Tools/ContentView.swift](AI%20Tools/ContentView.swift): Main UI layout and interaction
- [AI Tools/ViewModels/PlaygroundViewModel.swift](AI%20Tools/ViewModels/PlaygroundViewModel.swift): App state, provider switching, send flow, conversation persistence
- [AI Tools/Models/ChatModels.swift](AI%20Tools/Models/ChatModels.swift): Core models and provider enums
- [AI Tools/Models/PendingAttachment.swift](AI%20Tools/Models/PendingAttachment.swift): Attachment loading and image preprocessing
- [AI Tools/Networking/GeminiClient.swift](AI%20Tools/Networking/GeminiClient.swift): Gemini API integration
- [AI Tools/Networking/OpenAIClient.swift](AI%20Tools/Networking/OpenAIClient.swift): OpenAI API integration
- [AI Tools/Networking/AnthropicClient.swift](AI%20Tools/Networking/AnthropicClient.swift): Anthropic API integration
- [AI Tools/Views/ChatRenderingViews.swift](AI%20Tools/Views/ChatRenderingViews.swift): Message/media rendering components

## Known Limitations

- OpenAI and Anthropic attachment upload is not implemented yet.
- API keys are not stored in Keychain.
- There are no automated tests yet.

## License

No license file is currently included.
