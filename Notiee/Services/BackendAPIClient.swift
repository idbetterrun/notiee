import Foundation

// MARK: - Backend Quota (display-state truth lives on the backend)

/// Mirror of the backend `quota` payload. The client never computes these — it
/// only displays whatever the backend returns (`/me/quota` or the `quota` field
/// piggy-backed on `/ai/process`).
struct BackendQuota: Codable, Equatable, Sendable {
    let tier: String     // "free" | "pro"
    let used: Int
    let limit: Int
    let remaining: Int

    var isPro: Bool { tier == "pro" }
}

extension Notification.Name {
    /// Posted whenever the backend hands us a fresh quota snapshot (e.g. the
    /// `quota` field on a successful `/ai/process`). Phase 3's QuotaCard listens
    /// to refresh its display without a separate `/me/quota` round-trip.
    static let backendQuotaUpdated = Notification.Name("notiee.backendQuotaUpdated")
}

// MARK: - Typed backend errors

/// The backend contract is `{ error: { code, message } }`. We decode `code`
/// into a typed enum so call sites can branch (quota downgrade, paywall, re-auth)
/// without string matching.
enum BackendErrorCode: String, Sendable {
    case unauthorized = "UNAUTHORIZED"
    case upgradeRequired = "UPGRADE_REQUIRED"
    case quotaExceeded = "QUOTA_EXCEEDED"
    case badModel = "BAD_MODEL"
    case badRequest = "BAD_REQUEST"
    case upstreamError = "UPSTREAM_ERROR"
    case appleVerifyFailed = "APPLE_VERIFY_FAILED"
    case notImplemented = "NOT_IMPLEMENTED"
    case unknown = "UNKNOWN"

    init(rawValue: String) {
        switch rawValue {
        case "UNAUTHORIZED": self = .unauthorized
        case "UPGRADE_REQUIRED": self = .upgradeRequired
        case "QUOTA_EXCEEDED": self = .quotaExceeded
        case "BAD_MODEL": self = .badModel
        case "BAD_REQUEST": self = .badRequest
        case "UPSTREAM_ERROR": self = .upstreamError
        case "APPLE_VERIFY_FAILED": self = .appleVerifyFailed
        case "NOT_IMPLEMENTED": self = .notImplemented
        default: self = .unknown
        }
    }
}

struct BackendError: LocalizedError, Sendable {
    let code: BackendErrorCode
    let message: String
    let httpStatus: Int
    /// Present on `402 QUOTA_EXCEEDED` responses so the caller can drive the
    /// display without a follow-up `/me/quota`.
    let quota: BackendQuota?

    var errorDescription: String? { message }

    /// Networking / decoding failure that never reached a structured backend error.
    static func transport(_ underlying: Error) -> BackendError {
        BackendError(code: .unknown, message: underlying.localizedDescription, httpStatus: -1, quota: nil)
    }
}

// MARK: - Backend API client (Notiee free version only)

/// Thin transport for the self-hosted backend (`notiee-ping-stream`). Owns the
/// base URL, injects the Bearer token from `AuthService`, and decodes the
/// `{ error: { code, message } }` contract into `BackendError`.
///
/// This type only exists in the Notiee (free) target — the AI key lives on the
/// backend, so Notiee+ (BYOK) never touches it.
final class BackendAPIClient: @unchecked Sendable {
    static let shared = BackendAPIClient()

    /// Timeouts. `/ai/process` runs two upstream calls serially (≈60s each), so
    /// the client must wait well past that.
    enum Timeout {
        static let standard: TimeInterval = 60
        static let aiProcess: TimeInterval = 180
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = Timeout.aiProcess
            config.timeoutIntervalForResource = Timeout.aiProcess
            self.session = URLSession(configuration: config)
        }
    }

    /// Resolved base URL. Overridable at runtime (handy for pointing a device at
    /// a LAN dev box) via `UDK.backendBaseURL`; otherwise falls back to the
    /// compile-time default.
    var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: UDK.backendBaseURL),
           !override.isEmpty, let url = URL(string: override) {
            return url
        }
        return URL(string: BackendAPIClient.defaultBaseURLString)!
    }

    private static var defaultBaseURLString: String {
        #if DEBUG
        // Local `ALLOW_FAKE_APPLE=1 node index.js`. Simulator reaches the host
        // Mac via 127.0.0.1; for a physical device set UDK.backendBaseURL to the
        // Mac's LAN IP.
        return "http://127.0.0.1:9000"
        #else
        // 生产/TestFlight：腾讯 SCF 函数 URL（后续接自定义域名再换）。
        return "https://1330504927-70mg1o2c4d.ap-guangzhou.tencentscf.com"
        #endif
    }

    // MARK: - Requests

    /// POST a JSON body and return the decoded top-level object.
    /// - Parameter authorized: when true, injects `Authorization: Bearer <jwt>`
    ///   from `AuthService`. Auth endpoints like `/auth/apple` pass `false`.
    @discardableResult
    func postJSON(
        path: String,
        body: [String: Any],
        authorized: Bool = true,
        timeout: TimeInterval = Timeout.standard
    ) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let token = AuthService.shared.bearerToken else {
                throw BackendError(code: .unauthorized, message: "未登录", httpStatus: 401, quota: nil)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// GET a JSON object (always authorized).
    func getJSON(path: String, timeout: TimeInterval = Timeout.standard) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        guard let token = AuthService.shared.bearerToken else {
            throw BackendError(code: .unauthorized, message: "未登录", httpStatus: 401, quota: nil)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    // MARK: - Core send / decode

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendError(code: .unknown, message: "无效的服务器响应", httpStatus: -1, quota: nil)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(http.statusCode) else {
            throw Self.decodeError(json: json, status: http.statusCode)
        }

        return json ?? [:]
    }

    private static func decodeError(json: [String: Any]?, status: Int) -> BackendError {
        let errObj = json?["error"] as? [String: Any]
        let rawCode = errObj?["code"] as? String ?? "UNKNOWN"
        let message = errObj?["message"] as? String ?? "服务器错误 (\(status))"
        let quota = (json?["quota"] as? [String: Any]).flatMap(BackendQuota.init(dictionary:))
        return BackendError(code: BackendErrorCode(rawValue: rawCode), message: message, httpStatus: status, quota: quota)
    }
}

extension BackendQuota {
    init?(dictionary: [String: Any]) {
        guard let tier = dictionary["tier"] as? String,
              let used = dictionary["used"] as? Int,
              let limit = dictionary["limit"] as? Int,
              let remaining = dictionary["remaining"] as? Int else { return nil }
        self.init(tier: tier, used: used, limit: limit, remaining: remaining)
    }

    /// Broadcast this snapshot so display-state observers (Phase 3) can refresh.
    func broadcast() {
        NotificationCenter.default.post(name: .backendQuotaUpdated, object: nil, userInfo: ["quota": self])
    }
}
