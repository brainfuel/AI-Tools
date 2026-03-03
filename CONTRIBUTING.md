# Contributing to AI Tools

Thanks for your interest in contributing to AI Tools! This document explains how to get involved.

## Getting Started

1. Fork and clone the repository.
2. Open `AI Tools.xcodeproj` in Xcode 17 or later.
3. Select the **AI Tools** scheme and a run destination (for example **My Mac**).
4. Build and run to make sure everything works before you make changes.

You will need a valid API key for at least one provider (Gemini, OpenAI, or Anthropic) to test chat functionality.

## How to Contribute

### Reporting Bugs

Open an issue and include:

- A clear description of the problem.
- Steps to reproduce it.
- What you expected to happen versus what actually happened.
- Your macOS version and Xcode version.

### Suggesting Features

Open an issue with the **enhancement** label. Describe the feature, why it would be useful, and any ideas you have for how it could work.

### Submitting Code

1. Create a branch from `main` for your work. Use a descriptive name like `fix/attachment-crash` or `feature/streaming-responses`.
2. Make your changes in small, focused commits.
3. Test your changes by building and running the app.
4. Open a pull request against `main`.

## Code Style

- Follow standard Swift conventions and the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use the existing project structure: models go in `Models/`, networking clients in `Networking/`, views in `Views/`, and view models in `ViewModels/`.
- Keep files focused. If a file is growing large, consider splitting it.
- Use `async`/`await` for asynchronous work rather than callbacks.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) style where it makes sense:

```
feat: add streaming support for Anthropic client
fix: resolve crash when attachment exceeds size limit
docs: update provider support table in README
chore: update .gitignore
```

A short summary on the first line is the most important part. Add a body if the change needs more context.

## Pull Request Guidelines

- Keep pull requests focused on a single change.
- Describe what the PR does and why.
- Reference any related issues (for example `Closes #12`).
- Make sure the project builds without warnings before submitting.

## Project Structure

```
AI Tools/
├── Models/             Data models and enums
├── Networking/         API clients (Gemini, OpenAI, Anthropic)
├── Security/           Keychain storage
├── Storage/            Conversation persistence
├── ViewModels/         App state and business logic
└── Views/              SwiftUI view components
```

## Areas Where Help Is Welcome

Check the open issues for things to work on. Some areas that could use contributions:

- Attachment upload support for OpenAI and Anthropic providers.
- Automated tests.
- Accessibility improvements.
- Documentation.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
