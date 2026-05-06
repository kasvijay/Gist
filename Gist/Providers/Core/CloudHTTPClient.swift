import Foundation

actor CloudHTTPClient {
    static let shared = CloudHTTPClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - JSON POST

    func post<R: Decodable>(
        url: URL,
        headers: [String: String],
        body: some Encodable,
        responseType: R.Type
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, provider: nil)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: - Multipart Upload

    func uploadMultipart<R: Decodable>(
        url: URL,
        headers: [String: String],
        fileURL: URL,
        fieldName: String,
        mimeType: String = "audio/wav",
        additionalFields: [String: String] = [:],
        responseType: R.Type
    ) async throws -> R {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        var body = Data()
        let fileData = try Data(contentsOf: fileURL)

        // Additional fields
        for (key, value) in additionalFields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // File field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, provider: nil)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: - Raw Body Upload

    func uploadRaw<R: Decodable>(
        url: URL,
        headers: [String: String],
        fileURL: URL,
        contentType: String,
        responseType: R.Type
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let fileData = try Data(contentsOf: fileURL)
        request.httpBody = fileData

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, provider: nil)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: - GET with polling

    func get<R: Decodable>(
        url: URL,
        headers: [String: String],
        responseType: R.Type
    ) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data, provider: nil)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: - SSE Streaming

    func stream(
        url: URL,
        headers: [String: String],
        body: some Encodable,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Not an HTTP response")
        }
        guard (200...299).contains(httpResp.statusCode) else {
            // Collect error body
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw mapHTTPError(statusCode: httpResp.statusCode, message: errorMsg)
        }

        var accumulated = Data()
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                onChunk(payload)
                if let data = payload.data(using: .utf8) {
                    accumulated.append(data)
                }
            }
        }
        return accumulated
    }

    // MARK: - Test Connection

    func testConnection(url: URL, headers: [String: String]) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (_, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else { return false }
        return (200...299).contains(httpResp.statusCode)
    }

    // MARK: - Validation

    private func validateHTTPResponse(_ response: URLResponse, data: Data, provider: ProviderID?) throws {
        guard let httpResp = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Not an HTTP response")
        }
        guard (200...299).contains(httpResp.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw mapHTTPError(statusCode: httpResp.statusCode, message: message)
        }
    }

    private func mapHTTPError(statusCode: Int, message: String) -> ProviderError {
        switch statusCode {
        case 401, 403: return .authenticationFailed(message)
        case 413: return .fileTooLarge(maxBytes: 0)
        case 429: return .rateLimited(retryAfter: nil)
        default: return .invalidResponse("HTTP \(statusCode): \(message)")
        }
    }
}

// MARK: - Data extension for multipart

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
