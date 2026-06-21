import Foundation

enum EmberError: LocalizedError {
    case badURL, unauthorized, http(Int), offline
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid emberd address"
        case .unauthorized: return "Wrong or missing API key"
        case .http(let c): return "emberd error \(c)"
        case .offline: return "Can't reach emberd"
        }
    }
}

/// Thin async client for the emberd HTTP API. Reads (`/state`) are open;
/// mutating calls send `Authorization: Bearer <apiKey>`.
struct EmberClient: Sendable {
    let base: URL
    let apiKey: String

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    func state() async throws -> SaunaState { try await send("/state", method: "GET") }

    func control(_ body: ControlRequest) async throws -> SaunaState {
        try await send("/control", method: "POST", body: body)
    }

    func audio(action: String, volume: Int? = nil) async throws {
        struct Body: Encodable { let action: String; let volume: Int? }
        let _: EmptyResponse = try await send("/audio", method: "POST", body: Body(action: action, volume: volume))
    }

    func sessionStart() async throws {
        let _: EmptyResponse = try await send("/session/start", method: "POST", body: EmptyBody())
    }

    func sessionEnd() async throws -> SessionResult {
        try await send("/session/end", method: "POST", body: EmptyBody())
    }

    func registerActivityToken(_ token: String) async throws {
        struct Body: Encodable { let pushToken: String }
        let _: EmptyResponse = try await send("/activity/token", method: "POST", body: Body(pushToken: token))
    }

    // MARK: core

    private func send<T: Decodable>(_ path: String, method: String,
                                    body: (any Encodable)? = nil) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(AnyEncodable(body))
        }
        if method != "GET", !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await Self.session.data(for: req)
        } catch {
            throw EmberError.offline
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            if code == 401 { throw EmberError.unauthorized }
            throw EmberError.http(code)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try Self.decoder.decode(T.self, from: data)
    }
}

struct EmptyResponse: Decodable { }
private struct EmptyBody: Encodable { }

/// Erase a heterogeneous Encodable body so `send` can stay generic.
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ v: any Encodable) { value = v }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
