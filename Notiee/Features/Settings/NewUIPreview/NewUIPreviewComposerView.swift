import SwiftUI

/// 独立的全屏 Spark 页面，从底部进入；不从 dock 变形，导航栏那一排控件保持稳定。
struct NewUIPreviewComposerView: View {
    @EnvironmentObject private var sparkState: NewUIPreviewState
    @FocusState private var isInputFocused: Bool

    @State private var inputText = ""

    var body: some View {
        ZStack {
            Color.newUIPreviewBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.newUIPreviewPrimary)
                        .frame(width: 44, height: 44)
                        .newUIPreviewGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(NewUIPreviewPressStyle())
                .accessibilityLabel("关闭 Spark")
                .padding(.leading, 20)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Spark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.newUIPreviewPrimary)

                    Text(sparkState.dockText)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.newUIPreviewSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 30)

                Spacer(minLength: 24)

                composerInput
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                isInputFocused = true
            }
        }
    }

    private var composerInput: some View {
        HStack(alignment: .center, spacing: 12) {
            TextField("输入一句话…", text: $inputText)
                .focused($isInputFocused)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .tint(Color.newUIPreviewAccent)
                .frame(height: 38, alignment: .center)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.newUIPreviewAccent))
            }
            .buttonStyle(NewUIPreviewPressStyle())
            .accessibilityLabel("发送")
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .newUIPreviewGlass(in: Capsule())
    }

    private func close() {
        isInputFocused = false
        sparkState.collapse()
    }

    private func send() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputText = ""
    }
}
