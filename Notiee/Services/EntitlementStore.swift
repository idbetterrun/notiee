import Foundation
import Combine

/// 免费版的额度/档位**展示态**（只读，真值全在后端）。拉 `/me/quota`，并监听
/// `/ai/process` 捎带 quota 的 `.backendQuotaUpdated` 广播，免二次请求。
/// 仅用于 UI 展示，不参与任何 gating（gating 走 `CurrentEntitlement.tier`）。
/// 仅 Notiee（免费）target。Phase 4 由 StoreKit 购买流程扩展写入。
@MainActor
final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()

    @Published private(set) var quota: BackendQuota?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let api: BackendAPIClient
    private var observer: NSObjectProtocol?

    init(api: BackendAPIClient = .shared) {
        self.api = api
        observer = NotificationCenter.default.addObserver(
            forName: .backendQuotaUpdated, object: nil, queue: .main
        ) { [weak self] note in
            guard let q = note.userInfo?["quota"] as? BackendQuota else { return }
            MainActor.assumeIsolated { self?.quota = q }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// 展示用档位。未知时按最保守的免费档处理。
    var tier: ModelTier { quota?.isPro == true ? .pro : .free }

    var isLoggedIn: Bool { AuthService.shared.bearerToken != nil }

    func refresh() async {
        guard isLoggedIn else { quota = nil; return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let json = try await api.getJSON(path: "me/quota")
            if let q = BackendQuota(dictionary: json) { quota = q }
        } catch let e as BackendError {
            loadError = e.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
