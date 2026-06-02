import SwiftUI

struct EventCardView: View {
    let event: ScheduledEvent
    let currentDate: Date
    let tag: EventTag?
    let isLiveActive: Bool
    let showLiveToggle: Bool
    let onToggleLive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Tag badge
            Text(tag?.name ?? "普通")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tag?.color ?? .secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)

                if event.isAllDay {
                    Text("全天")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)
                } else {
                    Text(timeRange)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if showLiveToggle {
                Button(action: onToggleLive) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isLiveActive ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isLiveActive ? .green : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isLiveActive ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeRange: String {
        "\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))"
    }
}
