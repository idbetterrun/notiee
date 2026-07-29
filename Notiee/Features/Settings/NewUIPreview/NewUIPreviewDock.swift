import SwiftUI

struct NewUIPreviewSparkDock: View {
    @EnvironmentObject var sparkState: NewUIPreviewState

    var body: some View {
        Button(action: {
            sparkState.expand()
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

                Text("问问 Spark...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
            .newUIPreviewGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel("打开 Spark，问问 Spark")
    }
}

struct NewUIPreviewDockBar: View {
    @EnvironmentObject private var sparkState: NewUIPreviewState

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
                isSelected: sparkState.selectedTab == .today
            ) {
                sparkState.select(.today)
            }

            NewUIPreviewSparkDock()
                .frame(maxWidth: .infinity)

            NewUIPreviewCircleButton(
                symbol: "book.closed.fill",
                label: "记录",
                isSelected: sparkState.selectedTab == .records
            ) {
                sparkState.select(.records)
            }
        }
    }
}
