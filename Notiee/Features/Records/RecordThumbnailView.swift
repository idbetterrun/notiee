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
        ZStack {
            if record.isEncrypted {
                Rectangle().fill(Color.secondary.opacity(0.12))
                Image(systemName: "lock.fill").foregroundColor(.secondary)
            } else {
                if record.localImagePaths.count > 1 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.gray.opacity(0.3))
                        .frame(width: size * 0.8, height: size * 0.8)
                        .offset(y: -size * 0.15)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.gray.opacity(0.5))
                        .frame(width: size * 0.9, height: size * 0.9)
                        .offset(y: -size * 0.075)
                }

                Group {
                    switch record.source {
                    case .spark:
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: size * 0.42, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.361, green: 0.682, blue: 0.980),
                                                Color(red: 0.325, green: 0.980, blue: 0.671)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                    case .text:
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(NotieeColors.themed(.blue).opacity(0.12))
                            .overlay {
                                Image(systemName: "doc.text")
                                    .font(.title3)
                                    .foregroundStyle(NotieeColors.themed(.blue))
                            }
                    case .photo:
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(record.processingState.tint.opacity(0.12))
                                .overlay {
                                    Image(systemName: record.processingState == .completed ? "doc.richtext" : "photo")
                                        .font(.title3)
                                        .foregroundStyle(record.processingState.tint)
                                }
                        }
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                if record.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.25))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(size * 0.1)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loadImage()
        }
        .onChange(of: record.localImagePaths) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        guard !record.isEncrypted else { return }
        Task.detached(priority: .userInitiated) {
            guard let path = record.localImagePaths.first,
                  let data = LocalImageStore.readImageData(path: path),
                  let loadedImage = UIImage(data: data) else { return }
            await MainActor.run {
                self.image = loadedImage
            }
        }
    }
}
