import SwiftUI

struct NottiCitationRow: View {
    let citation: Citation
    let store: NotieeStore
    let onTap: ((UUID) -> Void)?

    var body: some View {
        if let record = store.records.first(where: { $0.id == citation.recordID }) {
            Button {
                onTap?(record.id)
            } label: {
                contentView
            }
            .buttonStyle(.plain)
        } else {
            contentView
        }
    }

    private var contentView: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.361, green: 0.682, blue: 0.980))
            VStack(alignment: .leading, spacing: 2) {
                Text(citation.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(citation.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
        .contentShape(Rectangle())
    }
}
