import SwiftUI

struct NewUIPreviewNottiDock: View {
    @EnvironmentObject var nottiState: NewUIPreviewState

    var body: some View {
        Button(action: {
            nottiState.expand()
        }) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, Color.newUIPreviewAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("问问 Notti...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.newUIPreviewPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
            .contentShape(Capsule())
            .newUIPreviewGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel("打开 Notti，问问 Notti")
    }
}

struct NewUIPreviewDockBar: View {
    @EnvironmentObject private var nottiState: NewUIPreviewState

    var body: some View {
        dockControls
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 0)
    }

    private var dockControls: some View {
        HStack(alignment: .center, spacing: 14) {
            NewUIPreviewCircleButton(
                symbol: "square.grid.2x2.fill",
                label: "Today",
                isSelected: nottiState.selectedTab == .today
            ) {
                nottiState.select(.today)
            }

            NewUIPreviewNottiDock()
                .frame(maxWidth: .infinity)

            NewUIPreviewCircleButton(
                symbol: "book.closed.fill",
                label: "记录",
                isSelected: nottiState.selectedTab == .records
            ) {
                nottiState.select(.records)
            }
        }
    }
}
