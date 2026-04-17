import XCTest
@testable import AI_Tools

final class APIClientErrorTests: XCTestCase {
    func testHTTP429IsRetryable() {
        let error = APIClientError.fromHTTP(
            provider: .grok,
            statusCode: 429,
            message: "Rate limit exceeded.",
            fallbackPrefix: "Request failed with status"
        )

        XCTAssertTrue(error.isRetryable)
    }

    func testHTTP401IsNotRetryable() {
        let error = APIClientError.fromHTTP(
            provider: .chatGPT,
            statusCode: 401,
            message: "Invalid API key.",
            fallbackPrefix: "Request failed with status"
        )

        XCTAssertFalse(error.isRetryable)
    }

    func testTransportTimeoutIsRetryable() {
        let wrapped = APIClientError.normalize(
            URLError(.timedOut),
            provider: .gemini
        )

        XCTAssertTrue(wrapped.isRetryable)
    }

    func testDescriptionIncludesProviderName() {
        let error = APIClientError.api(
            provider: .anthropic,
            statusCode: nil,
            message: "Bad request."
        )

        XCTAssertEqual(error.localizedDescription, "Anthropic: Bad request.")
    }
}

final class ChatMessageCodableTests: XCTestCase {
    func testChatMessageSynthesizedCodableRoundTrips() throws {
        let message = ChatMessage(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            role: .assistant,
            text: "hello",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            attachments: [
                AttachmentSummary(name: "image.png", mimeType: "image/png", previewBase64Data: "abc")
            ],
            generatedMedia: [
                GeneratedMedia(kind: .image, mimeType: "image/png", base64Data: "def")
            ],
            inputTokens: 12,
            outputTokens: 34,
            modelID: "gpt-4.1-mini"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.role, message.role)
        XCTAssertEqual(decoded.text, message.text)
        XCTAssertEqual(decoded.createdAt, message.createdAt)
        XCTAssertEqual(decoded.attachments.first?.name, "image.png")
        XCTAssertEqual(decoded.generatedMedia.first?.mimeType, "image/png")
        XCTAssertEqual(decoded.inputTokens, 12)
        XCTAssertEqual(decoded.outputTokens, 34)
        XCTAssertEqual(decoded.modelID, "gpt-4.1-mini")
    }
}
