import SwiftUI

/// 免费版选模型界面：列出精选目录，免费档模型可选，Pro 模型加锁并提示升级
/// （Phase 4 接付费墙）。仅 Notiee（免费）target。
struct ModelPickerView: View {
    private let selection = CuratedModelSelection.live
    private var tier: ModelTier { CurrentEntitlement.tier }

    @State private var selectedText = ""
    @State private var selectedVision = ""
    @State private var showProAlert = false

    var body: some View {
        Form {
            modelSection(title: "文本模型", kind: .text, current: selectedText) { selectedText = $0 }
            modelSection(title: "视觉模型", kind: .vision, current: selectedVision) { selectedVision = $0 }
        }
        .navigationTitle("模型选择")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedText = selection.textModelID(for: tier)
            selectedVision = selection.visionModelID(for: tier)
        }
        .alert("Pro 专属模型", isPresented: $showProAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("该模型为 Pro 会员专属，升级后即可使用。")
        }
    }

    @ViewBuilder
    private func modelSection(
        title: String,
        kind: CuratedModelKind,
        current: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Section(title) {
            ForEach(CuratedModelCatalog.models(kind: kind)) { model in
                let allowed = CuratedModelCatalog.isAllowed(model, for: tier)
                Button {
                    if allowed {
                        store(kind: kind, id: model.id)
                        onSelect(model.id)
                    } else {
                        showProAlert = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .foregroundColor(allowed ? .primary : .secondary)
                        if !allowed {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.id == current {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func store(kind: CuratedModelKind, id: String) {
        switch kind {
        case .text: selection.setTextModel(id)
        case .vision: selection.setVisionModel(id)
        }
    }
}
