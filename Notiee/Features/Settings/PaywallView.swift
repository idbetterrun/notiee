import SwiftUI
import StoreKit

/// Pro 订阅付费墙。审核 3.1.2：展示价格 / 周期 / 自动续订条款 + 恢复购买 + EULA/隐私链接。
/// 仅 Notiee（免费）target。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKit = StoreKitService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    priceAndPurchase
                    legalFooter
                }
                .padding()
            }
            .navigationTitle("Notiee Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("恢复购买") { Task { await storeKit.restore() } }
                }
            }
            .task { await storeKit.loadProducts() }
            .onChange(of: storeKit.purchaseState) { _, state in
                if state == .success { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill").font(.largeTitle).foregroundStyle(.yellow)
            Text("升级 Notiee Pro").font(.title2.bold())
            Text("解锁全部模型、Agent 智能体与更高额度")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("每月大幅提升处理额度")
            benefitRow("解锁全部文本 / 视觉模型")
            benefitRow("Notti Agent 智能体模式")
            benefitRow("对话不限轮数、记忆不限条数")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text)
            Spacer()
        }
    }

    private var priceAndPurchase: some View {
        VStack(spacing: 12) {
            if let product = storeKit.proProduct {
                Button {
                    Task { await storeKit.purchasePro() }
                } label: {
                    Text("\(product.displayPrice) / 月，订阅")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(storeKit.purchaseState == .purchasing)
            } else {
                ProgressView()
            }

            if case .failed(let msg) = storeKit.purchaseState {
                Text(msg).font(.caption).foregroundStyle(.red)
            }

            Text("订阅按月自动续订。除非在当前订阅周期结束前至少 24 小时关闭自动续订，否则将自动扣费续订。购买后可在 App Store 账户设置中管理或取消订阅。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var legalFooter: some View {
        HStack(spacing: 16) {
            legalLink(base: "UserAgreement", title: "用户协议 (EULA)")
            legalLink(base: "PrivacyPolicy", title: "隐私政策")
        }
        .font(.caption)
    }

    @ViewBuilder
    private func legalLink(base: String, title: String) -> some View {
        if let url = LegalDocument.bundleURL(base: base) {
            NavigationLink(title) {
                LegalHTMLView(url: url)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            Text(title).foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 统一付费墙 sheet，替代各处占位 alert。仅 Notiee target。
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { PaywallView() }
    }
}
