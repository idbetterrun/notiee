import Foundation
import StoreKit

/// StoreKit 2 订阅：加载商品、购买、恢复、监听交易更新。每笔已验证交易把签名后的
/// JWS 上报后端 `/subscription/verify`，由后端置档位；随后刷新 EntitlementStore。
/// 仅 Notiee（免费）target。
@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    static let proMonthlyID = "com.idbetterrun.notiee.pro.monthly"

    enum PurchaseState: Equatable {
        case idle, loading, purchasing, success, failed(String)
    }

    @Published private(set) var proProduct: Product?
    @Published private(set) var purchaseState: PurchaseState = .idle

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func purchasePro() async {
        guard let product = proProduct else {
            await loadProducts()
            return
        }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await report(verification)
                purchaseState = .success
            case .userCancelled, .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .loading
        try? await AppStore.sync()
        await reportCurrentEntitlements()
        purchaseState = .idle
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await verification in Transaction.updates {
                await self?.report(verification)
            }
        }
    }

    /// 遍历当前有效权益，逐一上报（恢复购买 / 启动补偿用）。
    private func reportCurrentEntitlements() async {
        for await verification in Transaction.currentEntitlements {
            await report(verification)
        }
        await EntitlementStore.shared.refresh()
    }

    /// 上报一笔交易：仅接受设备端验签通过的，把 JWS 交后端复验，然后 finish + 刷新档位。
    private func report(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        _ = try? await BackendAPIClient.shared.postJSON(
            path: "subscription/verify",
            body: ["signedTransaction": verification.jwsRepresentation])
        await transaction.finish()
        await EntitlementStore.shared.refresh()
    }
}
