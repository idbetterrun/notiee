import SwiftUI

struct RecordCardView: View {
    let record: NoteRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecordThumbnailView(record: record, size: 72, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)

                if record.isEncrypted {
                    Label("已加密拍记", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !record.isEncrypted, !record.summary.isEmpty {
                    Text(record.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Label(record.processingState.displayName, systemImage: record.processingState.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.processingState.tint)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
