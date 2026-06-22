import SwiftUI

struct SparkAgentChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Agent")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .glassSurface(in: RoundedRectangle(cornerRadius: 12), prominent: isOn)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 12) {
        SparkAgentChip(isOn: .constant(true))
        SparkAgentChip(isOn: .constant(false))
    }
    .padding()
}
