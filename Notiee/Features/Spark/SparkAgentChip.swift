import SwiftUI

struct SparkAgentChip: View {
    @Binding var isOn: Bool
    var locked: Bool = false
    var onLockedTap: () -> Void = {}

    var body: some View {
        Button {
            if locked {
                onLockedTap()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: locked ? "lock.fill" : "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Agent")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(isOn && !locked ? Color.white : Color.secondary)
            .glassSurface(in: RoundedRectangle(cornerRadius: 12), prominent: isOn && !locked)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn && !locked ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 0.5)
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
