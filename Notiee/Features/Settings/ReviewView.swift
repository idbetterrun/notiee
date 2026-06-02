import SwiftUI
import Charts


// MARK: - ReviewView
struct ReviewView: View {
    @ObservedObject var store: NotieeStore
    @State private var selectedRange: TimeRange = .today

    @AppStorage(UDK.tokenWarningThreshold) private var tokenWarningThreshold: Int = 0
    @AppStorage(UDK.accumulatedDeletedTokens) private var accumulatedDeletedTokens: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Picker("时间范围", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(spacing: 8) {
                    Text("预估 Token 消耗")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    let currentTokens = store.totalTokens(in: selectedRange)
                    Text("\(currentTokens)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(currentTokens >= tokenWarningThreshold && tokenWarningThreshold > 0 ? .orange : .accentColor)

                    Text(tokenComparisonText(for: currentTokens))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)

                if store.totalTokens(in: selectedRange) >= tokenWarningThreshold && tokenWarningThreshold > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Token 消耗已超提醒阈值 (\(tokenWarningThreshold) tk)")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                }

                let chartData = tokenDataByEvent()
                if !chartData.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("按日程消耗占比")
                            .font(.headline)
                            .padding(.horizontal)

                        Chart(chartData) { data in
                            SectorMark(
                                angle: .value("Tokens", data.tokens),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("日程", data.eventName))
                        }
                        .frame(height: 250)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }

                let topRecords = topRecordsByToken()
                if !topRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最耗 Token 的记录 (Top 5)")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(Array(topRecords.enumerated()), id: \.element.id) { index, record in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(record.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(record.capturedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(record.tokenUsage) tk")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                }

                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.secondary)
                    Text("已删除记录累计 Token 消耗（含彻底删除）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(accumulatedDeletedTokens) tk")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Text("声明：以上 Token 数仅为本地根据返回结果的粗略统计，不保证百分百与最终云端扣费结果一致。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding(.vertical)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("使用回顾")
    }

    private func tokenComparisonText(for tokens: Int) -> String {
        switch tokens {
        case 0:
            return "还没有消耗 Token 哦，快去拍记吧！"
        case 1..<10_000:
            return "大约相当于写了一篇小短文的数量。"
        case 10_000..<100_000:
            return "大约相当于读完了一本薄薄的杂志。"
        case 100_000..<500_000:
            return "大约相当于一两部中篇小说的字数啦！"
        case 500_000..<1_000_000:
            return "大概花了一本《西游记》的 Token 数咯！"
        default:
            return "天哪！这相当于读完了好几本大部头巨著！"
        }
    }

    private func topRecordsByToken() -> [NoteRecord] {
        let records = store.records(in: selectedRange)
        return Array(records.sorted(by: { $0.tokenUsage > $1.tokenUsage }).prefix(5))
    }

    struct EventTokenData: Identifiable {
        let id = UUID()
        let eventName: String
        let tokens: Int
    }

    private func tokenDataByEvent() -> [EventTokenData] {
        let records = store.records(in: selectedRange)
        var dict: [String: Int] = [:]

        for record in records {
            let name: String
            if let eventID = record.eventID, let event = store.events.first(where: { $0.id == eventID }) {
                name = event.title
            } else {
                name = "未分类"
            }
            dict[name, default: 0] += record.tokenUsage
        }

        return dict.map { EventTokenData(eventName: $0.key, tokens: $0.value) }
            .sorted(by: { $0.tokens > $1.tokens })
    }
}

