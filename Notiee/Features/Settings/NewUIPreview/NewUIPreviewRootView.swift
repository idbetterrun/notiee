import SwiftUI

/// 实验室里的「新 UI 预览」宿主页面。
/// 只用于查看 notiee-newfront 那套导航方向，不接主 App 的任何数据，也不影响主 App 的界面。
/// 左上角按 App Store 交互惯例改成菜单键：展开后才有「退出预览」。
struct NewUIPreviewRootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sparkState = NewUIPreviewState()
    @Namespace private var sparkNamespace

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            NewUIPreviewTodayView()
                .environmentObject(sparkState)

            if sparkState.isExpanded {
                NewUIPreviewComposerView()
                    .environmentObject(sparkState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        dismiss()
                    } label: {
                        Label("退出预览", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("菜单")
            }
        }
        .onAppear {
            sparkState.namespace = sparkNamespace
        }
    }
}
