import SwiftUI
import Combine

// 新 UI 预览：从 notiee-newfront (NotieeSparkDemo) 原样搬入，仅重命名以避免与主 App 符号冲突。
// 这里的所有类型都只服务于实验室里的「新 UI 预览」，不参与主 App 的任何界面或数据流程。

enum NewUIPreviewTab {
    case today
    case records
}

final class NewUIPreviewState: ObservableObject {
    @Published var isExpanded = false
    @Published var expansionProgress: CGFloat = 0
    @Published var dockText: String = ""
    @Published var todayEntryCount = 3
    @Published var consecutiveDays = 8
    @Published var selectedTab: NewUIPreviewTab = .today
    var namespace: Namespace.ID? = nil

    private var timer: AnyCancellable?

    init() {
        updateDockText()
        startContextTimer()
    }

    func toggle() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)) {
            isExpanded.toggle()
        }
    }

    func expand() {
        guard !isExpanded else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)) {
            isExpanded = true
        }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9, blendDuration: 0)) {
            isExpanded = false
        }
    }

    func select(_ tab: NewUIPreviewTab) {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedTab = tab
        }
    }

    func updateDockText() {
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 21 {
            dockText = "✨ 今天过得怎么样？"
        } else if todayEntryCount > 0 {
            dockText = "✨ 已记录 \(todayEntryCount) 条拍记"
        } else if consecutiveDays > 1 {
            dockText = "✨ 已陪伴你第 \(consecutiveDays) 天"
        } else {
            dockText = "✨ 今天想记录什么？"
        }
    }

    private func startContextTimer() {
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDockText()
            }
    }
}
