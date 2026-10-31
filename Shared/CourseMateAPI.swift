//
//  CourseMateAPI.swift
//  The whole client surface: two fire-and-forget POSTs plus a session call.
//
import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case transport
    case status(Int, String)
    case noSessionID

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Server URL is not valid."
        case .transport:
            return "No HTTP response — is the server running and reachable?"
        case let .status(code, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(trimmed)"
        case .noSessionID:
            return "The server answered without a session_id."
        }
    }
}

enum CourseMateAPI {
    static func post(
        base: String,
        token: String,
        path: String,
        payload: [String: Any],
        timeout: TimeInterval = 15
    ) async throws -> Data {
        guard let url = CMSettings.url(base + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, String(decoding: data.prefix(400), as: UTF8.self))
        }
        return data
    }

    static func get(base: String, token: String, path: String, timeout: TimeInterval = 15) async throws -> Data {
        guard let url = CMSettings.url(base + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, String(decoding: data.prefix(400), as: UTF8.self))
        }
        return data
    }

    static func createSession(base: String, token: String, course: String) async throws -> String {
        let data = try await post(
            base: base,
            token: token,
            path: "/api/session",
            payload: ["course": course]
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let id = object?["session_id"] as? String { return id }
        if let id = object?["id"] as? String { return id }
        throw APIError.noSessionID
    }

    /// Used by the "Test server" button so a wrong IP is discovered in the app
    /// rather than 30 seconds into a lecture with no frames arriving.
    static func health(base: String, token: String) async throws -> String {
        guard let url = CMSettings.url(base + "/api/health") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data.prefix(400), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "HTTP \(code) \(body)"
    }
}
