import SwiftUI

struct SparkModelChip: View {
    let title: String
    let icon: String
    let options: [(id: String, label: String)]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { opt in
                Button {
                    onSelect(opt.id)
                } label: {
                    if opt.id == selectedID {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color.secondary)
            .glassSurface(in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
