import SwiftUI

struct NewUIPreviewTodayView: View {
    @EnvironmentObject var sparkState: NewUIPreviewState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text(sparkState.selectedTab == .today ? "Today" : "记录")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 64)
                        .padding(.horizontal, 20)

                    ForEach(0..<6) { index in
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(sparkState.selectedTab == .today ? .white.opacity(0.11) : .white.opacity(0.07))
                            .frame(height: 120)
                            .overlay(
                                Text(sparkState.selectedTab == .today ? "拍记 #\(index + 1)" : "记录 #\(index + 1)")
                                    .foregroundStyle(.white.opacity(0.48))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 136)
            }

            NewUIPreviewDockBar()
        }
    }
}
