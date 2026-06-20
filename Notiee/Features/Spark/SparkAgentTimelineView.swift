import SwiftUI

struct SparkAgentTimelineView: View {
    let actions: [AgentAction]
    let runningToolName: String?   // 非空表示工作中
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let running = runningToolName {
                let p = AgentToolPresentation.forName(running)
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Image(systemName: p.icon).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(p.runningText).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !actions.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle").font(.caption2)
                        Text("执行了 \(actions.count) 步").font(.caption.weight(.medium))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actions) { action in
                            let p = AgentToolPresentation.forName(action.toolName)
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: action.result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(action.result.success ? .green : .red)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Image(systemName: p.icon).font(.caption2).foregroundStyle(.secondary)
                                        Text(p.displayName).font(.caption.weight(.medium))
                                    }
                                    Text(action.result.message)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.06)))
        .padding(.horizontal, 16)
    }
}
