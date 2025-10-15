import Foundation

struct BillsAPI {
    let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchBills(monthKey: String) async throws -> [Bill] {
        try await send(
            path: "/api/bills",
            query: [URLQueryItem(name: "month", value: monthKey)]
        )
    }

    func createBill(_ payload: BillRequest) async throws -> Bill {
        let data = try encoder.encode(payload)
        return try await send(path: "/api/bills", method: "POST", body: data)
    }

    func updateBill(id: String, payload: BillUpdateRequest) async throws -> Bill {
        let data = try encoder.encode(payload)
        return try await send(path: "/api/bills/\(id)", method: "PUT", body: data)
    }

    func deleteBill(id: String) async throws {
        try await sendVoid(path: "/api/bills/\(id)", method: "DELETE")
    }

    func setBillPaid(id: String, isPaid: Bool, monthKey: String) async throws {
        let data = try encoder.encode(PaidRequest(isPaid: isPaid, month: monthKey))
        _ = try await send(path: "/api/bills/\(id)/paid", method: "POST", body: data) as PaidResponse
    }

    func askBillsGPT(message: String, monthKey: String) async throws -> String {
        let data = try encoder.encode(ChatRequest(message: message, month: monthKey))
        let response: ChatResponse = try await send(path: "/api/chat", method: "POST", body: data)
        return response.reply
    }

    func registerPushToken(token: String, platform: String) async throws {
        let data = try encoder.encode(PushRegistrationRequest(token: token, platform: platform))
        _ = try await send(path: "/api/push/register", method: "POST", body: data) as PushRegistrationResponse
    }

    func unregisterPushToken(token: String) async throws {
        let data = try encoder.encode(PushRegistrationRequest(token: token, platform: nil))
        _ = try await send(path: "/api/push/unregister", method: "POST", body: data) as PushRegistrationResponse
    }

    func sendUpcomingPush(monthKey: String?) async throws -> PushNotificationSummary {
        let data = try encoder.encode(UpcomingPushRequest(month: monthKey))
        return try await send(path: "/api/push/send-upcoming", method: "POST", body: data)
    }
}

extension BillsAPI {
    struct BillRequest: Encodable {
        var id: String?
        var name: String
        var dueDay: Int
        var amount: Double
        var notes: String
    }

    struct BillUpdateRequest: Encodable {
        var name: String?
        var dueDay: Int?
        var amount: Double?
        var notes: String?
    }

    private struct PaidRequest: Encodable {
        var isPaid: Bool
        var month: String
    }

    private struct PaidResponse: Decodable {
        var id: String
        var month: String
        var isPaid: Bool
    }

    private struct ChatRequest: Encodable {
        var message: String
        var month: String
    }

    private struct ChatResponse: Decodable {
        var reply: String
    }

    private struct PushRegistrationRequest: Encodable {
        var token: String
        var platform: String?
    }

    private struct PushRegistrationResponse: Decodable {
        var ok: Bool
        var token: String?
    }

    private struct UpcomingPushRequest: Encodable {
        var month: String?
    }

    private struct ServerErrorResponse: Decodable {
        var error: String
        var details: String?
    }
}

private extension BillsAPI {
    func send<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        let data = try await perform(path: path, method: method, query: query, body: body)

        if data.isEmpty, T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
            return empty
        }

        return try decoder.decode(T.self, from: data)
    }

    func sendVoid(
        path: String,
        method: String = "POST",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws {
        _ = try await perform(path: path, method: method, query: query, body: body)
    }

    struct EmptyResponse: Decodable {
        init() {}
    }

    func perform(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?
    ) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components == nil {
            throw BillsAPIError.invalidBaseURL
        }
        components?.path = (components?.path ?? "") + path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw BillsAPIError.invalidRequestPath
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BillsAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let serverError = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw BillsAPIError.server(message: serverError.error, details: serverError.details, statusCode: http.statusCode)
            }
            throw BillsAPIError.server(message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode), details: nil, statusCode: http.statusCode)
        }

        return data
    }
}

enum BillsAPIError: LocalizedError {
    case invalidBaseURL
    case invalidRequestPath
    case invalidResponse
    case server(message: String, details: String?, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Bills API base URL is invalid."
        case .invalidRequestPath:
            return "Could not construct the requested API path."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case let .server(message, details, status):
            if let details {
                return "Server error (\(status)): \(message) — \(details)"
            }
            return "Server error (\(status)): \(message)"
        }
    }
}
