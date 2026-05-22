import SwiftUI

struct RecordThumbnailView: View {
    let record: NoteRecord
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var image: UIImage? = nil
    
    init(record: NoteRecord, size: CGFloat = 72, cornerRadius: CGFloat = 12) {
        self.record = record
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback to placeholder
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(record.processingState.tint.opacity(0.12))
                    .overlay {
                        Image(systemName: record.processingState == .completed ? "doc.richtext" : "photo")
                            .font(.title3)
                            .foregroundStyle(record.processingState.tint)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            loadImage()
        }
        .onChange(of: record.localImagePath) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            if let loadedImage = await MainActor.run(body: { LocalImageStore.shared.loadImage(path: record.localImagePath) }) {
                await MainActor.run {
                    self.image = loadedImage
                }
            }
        }
    }
}
