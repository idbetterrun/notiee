import SwiftUI

/// 「我」tab 的额度卡片：进度环 + 「本月 X / N 篇」+ 档位 + Pro 入口。
/// 断网/未登录/加载中都有兜底态。真值来自 `EntitlementStore`。仅 Notiee target。
struct QuotaCard: View {
    @StateObject private var entitlement = EntitlementStore.shared
    @State private var showProUpsell = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !entitlement.isLoggedIn {
                Label("登录后查看本月额度", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let q = entitlement.quota {
                content(q)
            } else if entitlement.isLoading {
                HStack { ProgressView(); Text("加载额度…").font(.subheadline).foregroundStyle(.secondary) }
            } else {
                HStack {
                    Text(entitlement.loadError == nil ? "暂无额度信息" : "额度加载失败")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("重试") { Task { await entitlement.refresh() } }
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
        .task { await entitlement.refresh() }
        .alert("升级 Pro 会员", isPresented: $showProUpsell) {
            Button("知道了", role: .cancel) {}
            // TODO(Phase 4): present PaywallView
        } message: {
            Text("升级 Pro 即可大幅提升每月额度，并解锁全部模型。")
        }
    }

    @ViewBuilder
    private func content(_ q: BackendQuota) -> some View {
        HStack(spacing: 16) {
            ring(used: q.used, limit: q.limit)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(q.isPro ? "Pro 会员" : "免费版")
                    .font(.subheadline.weight(.semibold))
                Text("本月 \(q.used) / \(q.limit) 篇")
                    .font(.headline)
                Text("剩余 \(max(0, q.remaining)) 篇")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !q.isPro {
                Button {
                    showProUpsell = true
                } label: {
                    Text("升级 Pro")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ring(used: Int, limit: Int) -> some View {
        let fraction = limit > 0 ? min(1, Double(used) / Double(limit)) : 0
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(fraction * 100))%")
                .font(.caption2.weight(.semibold))
        }
    }
}
