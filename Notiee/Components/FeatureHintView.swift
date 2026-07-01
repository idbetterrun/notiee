import SwiftUI

struct FeatureHintView: ViewModifier {
    let featureKey: String
    let title: String
    let message: String
    let iconName: String

    @State private var showHint = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if showHint {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture { dismiss() }

                        VStack(spacing: 20) {
                            Image(systemName: iconName)
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)

                            Text(title)
                                .font(.title3.weight(.semibold))

                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                dismiss()
                            } label: {
                                Text("知道了")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 40)
                    }
                    .transition(.opacity)
                }
            }
            .onAppear {
                if !UserDefaults.standard.bool(forKey: featureKey) {
                    showHint = true
                }
            }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            showHint = false
        }
        UserDefaults.standard.set(true, forKey: featureKey)
    }
}

extension View {
    func featureHint(key: String, title: String, message: String, icon: String) -> some View {
        modifier(FeatureHintView(featureKey: key, title: title, message: message, iconName: icon))
    }
}
