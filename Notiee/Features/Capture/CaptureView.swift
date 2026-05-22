import SwiftUI
import PhotosUI

struct CaptureView: View {
    @StateObject private var viewModel: CaptureViewModel
    @State private var showsCaptureFlash = false
    @State private var shutterIsPressed = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var presentedRecord: NoteRecord?

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: CaptureViewModel.sample())
    }

    @MainActor
    init(viewModel: CaptureViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color(.notieeCameraBackground)
                .ignoresSafeArea()

            if viewModel.cameraManager.status == .ready {
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .ignoresSafeArea()
            } else if viewModel.cameraManager.status == .unauthorized {
                VStack {
                    Image(systemName: "camera.slash")
                        .font(.largeTitle)
                        .padding(.bottom, 8)
                    Text("需要相机权限才能进行拍记")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.7))
            }

            VStack(spacing: 22) {
                contextHeader

                viewfinder

                Spacer()

                latestCaptureStatus
                captureControls
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)

            if showsCaptureFlash {
                Color.white
                    .opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsCaptureFlash)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: shutterIsPressed)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    private var contextHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.currentEvent == nil ? "tray.full" : "calendar.badge.clock")
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.contextTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Text(viewModel.contextSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.06))

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)

            VStack {
                HStack {
                    Label("AUTO", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.notieeCameraBackground).opacity(0.58), in: Capsule())

                    Spacer()

                    Text(viewModel.currentEvent?.kind.displayName ?? "INBOX")
                        .font(.caption.monospaced().weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.notieeCameraBackground).opacity(0.58), in: Capsule())
                }
                .foregroundStyle(.white.opacity(0.86))

                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(.white.opacity(0.54))

                    Text(viewModel.latestRecord?.title ?? viewModel.contextTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                HStack {
                    Image(systemName: "scope")
                    Text(Date.now.formatted(.dateTime.hour().minute()))
                        .font(.caption.monospacedDigit().weight(.semibold))

                    Spacer()

                    if !viewModel.capturedRecords.isEmpty {
                        Text("\(viewModel.capturedRecords.count) 张")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(18)

            CornerGuides()
                .stroke(.white.opacity(0.48), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(18)
        }
        .aspectRatio(0.75, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var latestCaptureStatus: some View {
        if let latestRecord = viewModel.latestRecord {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(latestRecord.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(latestRecord.processingState.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var captureControls: some View {
        HStack(alignment: .center) {
            Button {
                if let latest = viewModel.latestRecord {
                    presentedRecord = latest
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .frame(width: 58, height: 58)
                        .overlay {
                            if let latestRecord = viewModel.latestRecord,
                               let image = LocalImageStore.shared.loadImage(path: latestRecord.localImagePath) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            } else {
                                Image(systemName: viewModel.latestRecord == nil ? "tray" : "photo")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }

                    if !viewModel.capturedRecords.isEmpty {
                        Text("\(viewModel.capturedRecords.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .accessibilityLabel("暂存区")

            Spacer()

            Button {
                capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 74, height: 74)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.42), lineWidth: 6)
                            .frame(width: 88, height: 88)
                    }
                    .overlay {
                        Circle()
                            .stroke(Color(.notieeCameraBackground).opacity(0.18), lineWidth: 1)
                            .frame(width: 64, height: 64)
                    }
                    .scaleEffect(shutterIsPressed ? 0.94 : 1)
            }
            .accessibilityLabel("拍摄")

            Spacer()

            PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityLabel("相册")
            .onChange(of: selectedItem) { newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.importPhoto(image)
                    }
                    selectedItem = nil
                }
            }
        }
        .padding(.horizontal, 6)
        .sheet(item: $presentedRecord) { record in
            if let store = viewModel.store {
                NavigationStack {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                }
            }
        }
    }

    private func capture() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            viewModel.capturePhoto()
            shutterIsPressed = true
            showsCaptureFlash = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            shutterIsPressed = false
            showsCaptureFlash = false
        }
    }
}

private struct CornerGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 34

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private extension UIColor {
    static let notieeCameraBackground = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1.0)
}

private extension ScheduledEvent.Kind {
    var displayName: String {
        switch self {
        case .course:
            "课程"
        case .meeting:
            "会议"
        case .uncategorized:
            "未分类"
        }
    }
}

#Preview {
    CaptureView()
}
