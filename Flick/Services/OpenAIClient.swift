//
//  OpenAIClient.swift
//  Flick
//

import Foundation

struct OpenAIClient {
    var apiKey: String?
    var urlSession: URLSession
    var planningModel: String
    var imageModel: String

    init(
        credentials: [String: String] = CredentialVault().loadValues(),
        urlSession: URLSession = .shared,
        planningModel: String = "gpt-5.5",
        imageModel: String = "gpt-image-2"
    ) {
        apiKey = credentials["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
        self.planningModel = planningModel
        self.imageModel = imageModel
    }

    func createStructuredResponse<T: Decodable>(
        instructions: String,
        input: Any,
        schemaName: String,
        schema: [String: Any],
        as type: T.Type
    ) async throws -> T {
        let body: [String: Any] = [
            "model": planningModel,
            "instructions": instructions,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        let data = try await postJSON(body, to: URL(string: "https://api.openai.com/v1/responses")!)
        let responseText = try OpenAIResponsesEnvelope(data: data).outputText()
        guard let jsonData = responseText.data(using: .utf8) else {
            throw OpenAIClientError.invalidResponse("The response text was not UTF-8.")
        }
        return try JSONDecoder.flick.decode(T.self, from: jsonData)
    }

    func generateImage(prompt: String, settings: SlideshowImageGenerationSettings) async throws -> GeneratedSlideImage {
        let body: [String: Any] = [
            "model": imageModel,
            "prompt": prompt,
            "size": settings.size,
            "quality": settings.quality,
            "n": 1,
            "output_format": "png"
        ]

        let data = try await postJSON(body, to: URL(string: "https://api.openai.com/v1/images/generations")!)
        let response = try JSONDecoder().decode(OpenAIImageGenerationResponse.self, from: data)
        guard let encodedImage = response.data.first?.b64JSON, let imageData = Data(base64Encoded: encodedImage) else {
            throw OpenAIClientError.invalidResponse("The image generation response did not include a base64 image.")
        }

        return GeneratedSlideImage(
            data: imageData,
            contentType: "image/png",
            fileExtension: "png",
            width: settings.width,
            height: settings.height
        )
    }

    private func postJSON(_ body: [String: Any], to url: URL) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse("OpenAI did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIClientError.requestFailed(statusCode: httpResponse.statusCode, message: OpenAIErrorMessage(data: data).message)
        }
        return data
    }
}

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "OpenAI API key is required for slideshow generation."
        case let .requestFailed(statusCode, message):
            "OpenAI request failed with HTTP \(statusCode): \(message)"
        case let .invalidResponse(message):
            message
        }
    }
}

private struct OpenAIImageGenerationResponse: Decodable {
    struct ImageData: Decodable {
        var b64JSON: String?

        private enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    var data: [ImageData]
}

private struct OpenAIErrorMessage {
    var message: String

    init(data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            self.message = String(data: data, encoding: .utf8) ?? "Unknown error"
            return
        }
        self.message = message
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    private struct OutputItem: Decodable {
        var content: [ContentItem]?
    }

    private struct ContentItem: Decodable {
        var text: String?
    }

    private var output: [OutputItem]?
    private var outputTextFallback: String?

    private enum CodingKeys: String, CodingKey {
        case output
        case outputTextFallback = "output_text"
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    func outputText() throws -> String {
        if let outputTextFallback, !outputTextFallback.isEmpty {
            return outputTextFallback
        }

        let text = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !text.isEmpty else {
            throw OpenAIClientError.invalidResponse("The Responses API result did not include output text.")
        }
        return text
    }
}
