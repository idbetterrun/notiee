import SwiftUI

/// 免费版「回顾」：以「篇数」为口径（替代 Notiee+ 的 token 版 `ReviewView`）。
/// 顶部 QuotaCard 展示本月额度，下面按笔记标题聚合本月拍记篇数。仅 Notiee target。
struct UsageReviewView: View {
    @ObservedObject var store: NotieeStore

    private var thisMonthRecords: [NoteRecord] {
        let cal = Calendar.current
        return store.records.filter {
            !$0.isDeleted && cal.isDate($0.capturedAt, equalTo: Date(), toGranularity: .month)
        }
    }

    /// 按标题聚合的本月篇数（Top 8），降序。
    private var topGroups: [(title: String, count: Int)] {
        Dictionary(grouping: thisMonthRecords, by: { $0.title })
            .map { (title: $0.key.isEmpty ? "未命名" : $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        List {
            Section {
                QuotaCard()
            }

            Section("本月拍记") {
                HStack {
                    Text("共处理")
                    Spacer()
                    Text("\(thisMonthRecords.count) 篇")
                        .font(.headline)
                }
            }

            if !topGroups.isEmpty {
                Section("按笔记分布") {
                    ForEach(topGroups, id: \.title) { group in
                        HStack {
                            Text(group.title).lineLimit(1)
                            Spacer()
                            Text("\(group.count) 篇")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("回顾")
        .navigationBarTitleDisplayMode(.inline)
    }
}
