//
//  ImageGenerator.swift
//  StrategyForge
//
//  Text-to-image generation via the providers' IMAGE APIs (not the coding CLIs, which are
//  text-only). Uses the same API keys Coral already stores in the Keychain:
//   • OpenAI  → POST /v1/images/generations, model `gpt-image-1` (returns base64 PNG).
//   • Google  → Imagen 3 via the Gemini API `:predict` endpoint (returns base64 PNG).
//  One async entry point returns raw PNG data; the caller renders + saves it. Errors are
//  surfaced verbatim so a bad key / unverified org / quota reads honestly, never a silent fail.
//

import Foundation

enum ImageAspect: String, CaseIterable, Identifiable {
    case square, landscape, portrait
    var id: String { rawValue }
    /// OpenAI wants an explicit pixel size; Imagen wants an aspect-ratio string.
    var openAISize: String {
        switch self {
        case .square:    return "1024x1024"
        case .landscape: return "1536x1024"
        case .portrait:  return "1024x1536"
        }
    }
    var imagenRatio: String {
        switch self {
        case .square:    return "1:1"
        case .landscape: return "16:9"
        case .portrait:  return "9:16"
        }
    }
}

enum ImageGenError: LocalizedError {
    case unsupportedProvider(AIProvider)
    case missingKey(AIProvider)
    case http(Int, String)
    case badResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let p): return "\(p.displayName) doesn't offer image generation."
        case .missingKey(let p):          return "No \(p.displayName) API key is set."
        case .http(let code, let body):   return "HTTP \(code): \(body)"
        case .badResponse:                return "The image service returned no image."
        case .network(let m):             return m
        }
    }
}

enum ImageGenerator {
    /// Which providers can actually generate images (used to build the picker).
    static let supportedProviders: [AIProvider] = [.openai, .gemini]

    /// Generate one image for `prompt`. Returns raw PNG bytes. Throws `ImageGenError` on any
    /// failure (surfaced to the user).
    static func generate(prompt: String, provider: AIProvider, aspect: ImageAspect, apiKey: String) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ImageGenError.missingKey(provider) }
        switch provider {
        case .openai: return try await openAI(prompt: prompt, aspect: aspect, key: key)
        case .gemini: return try await imagen(prompt: prompt, aspect: aspect, key: key)
        default:      throw ImageGenError.unsupportedProvider(provider)
        }
    }

    // MARK: OpenAI — gpt-image-1

    private static func openAI(prompt: String, aspect: ImageAspect, key: String) async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/images/generations") else { throw ImageGenError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-1",
            "prompt": prompt,
            "size": aspect.openAISize,
            "n": 1,
        ])
        let (data, resp) = try await send(req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ImageGenError.http(code, errorText(data)) }
        // { "data": [ { "b64_json": "..." } ] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]],
              let b64 = arr.first?["b64_json"] as? String,
              let bytes = Data(base64Encoded: b64) else { throw ImageGenError.badResponse }
        return bytes
    }

    // MARK: Google — Imagen 3 (Gemini API)

    private static func imagen(prompt: String, aspect: ImageAspect, key: String) async throws -> Data {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict"
        guard let url = URL(string: endpoint) else { throw ImageGenError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")   // key in a header, not the URL
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "instances": [["prompt": prompt]],
            "parameters": ["sampleCount": 1, "aspectRatio": aspect.imagenRatio],
        ])
        let (data, resp) = try await send(req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ImageGenError.http(code, errorText(data)) }
        // { "predictions": [ { "bytesBase64Encoded": "..." } ] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["predictions"] as? [[String: Any]],
              let b64 = arr.first?["bytesBase64Encoded"] as? String,
              let bytes = Data(base64Encoded: b64) else { throw ImageGenError.badResponse }
        return bytes
    }

    // MARK: Shared

    private static func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: req) }
        catch { throw ImageGenError.network(error.localizedDescription) }
    }

    /// Pull a human message out of a provider error body (both use `{ "error": { "message" } }`),
    /// else the raw text, trimmed to something showable.
    private static func errorText(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String { return msg }
        return String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "Unknown error"
    }
}
