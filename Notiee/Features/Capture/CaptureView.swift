import SwiftUI
import PhotosUI
import AVFoundation
import AVKit

struct CaptureView: View {
    @StateObject private var viewModel: CaptureViewModel
    @State private var showsCaptureFlash = false
    @State private var shutterIsPressed = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var presentedRecord: NoteRecord?
    @State private var currentZoomFactor: CGFloat = 1.0

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
            Color.black
                .ignoresSafeArea()
            
            CameraControlView {
                capture()
            }

            VStack(spacing: 0) {
                topBar
                
                infoBannerView
                
                Spacer()

                viewfinder
                
                Spacer()

                captureModeSwitcher
                
                bottomControls
                    .padding(.bottom, 10)
            }
            .padding(.top, 10)
            .padding(.bottom, 24)

            if showsCaptureFlash {
                Color.black
                    .opacity(0.8)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeOut(duration: 0.1), value: showsCaptureFlash)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    private var topBar: some View {
        HStack {
            // Flash button
            Button {
                let current = viewModel.cameraManager.flashMode
                viewModel.cameraManager.flashMode = current == .auto ? .on : (current == .on ? .off : .auto)
            } label: {
                Image(systemName: flashIcon(for: viewModel.cameraManager.flashMode))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(viewModel.cameraManager.flashMode == .on ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(viewModel.cameraManager.flashMode == .on ? Color.yellow : Color.white.opacity(0.15), in: Circle())
            }

            Spacer()

            Text(viewModel.contextTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            // Event Selection (Folder)
            Menu {
                let deduplicated = deduplicateEvents(viewModel.events)
                let todayAllDay = viewModel.todayAllDayEvent
                let currentNonAllDay: ScheduledEvent? = {
                    if let e = viewModel.currentEvent, !e.isAllDay {
                        return e
                    }
                    return nil
                }()
                let todaySpecials = CalendarService.shared.specialDayEvents(for: viewModel.currentDate)
                let todaySpecialTitles = Set(todaySpecials.map { $0.title })
                
                // 1. 全天事件
                if let allDay = todayAllDay {
                    Button {
                        viewModel.selectedEventID = allDay.id
                    } label: {
                        HStack {
                            Text(allDay.title)
                            Spacer()
                            if viewModel.selectedEventID == allDay.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                // 2. 当前非全天事件
                if let current = currentNonAllDay {
                    Button {
                        viewModel.selectedEventID = current.id
                    } label: {
                        HStack {
                            Text(current.title)
                            Spacer()
                            if viewModel.selectedEventID == current.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                // 3. 未分类
                Button {
                    viewModel.selectedEventID = nil
                } label: {
                    HStack {
                        Text("未分类")
                        Spacer()
                        if viewModel.selectedEventID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // Filter remaining: exclude pinned items, exclude holidays/birthdays unless today IS that holiday
                let pinnedIDs: Set<UUID?> = [todayAllDay?.id, currentNonAllDay?.id]
                let remaining = deduplicated.filter { event in
                    guard !pinnedIDs.contains(event.id) else { return false }
                    // If today IS this special event, allow it below divider too
                    if todaySpecialTitles.contains(event.title) {
                        return true
                    }
                    // Exclude other special all-day events from the list
                    return !CalendarService.shared.isSpecialAllDayEvent(event)
                }
                
                if !remaining.isEmpty {
                    Divider()
                    ForEach(remaining) { event in
                        Button {
                            viewModel.selectedEventID = event.id
                        } label: {
                            HStack {
                                Text(event.title)
                                Spacer()
                                if viewModel.selectedEventID == event.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Color.white, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    private func flashIcon(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        default: return "bolt.badge.a.fill"
        }
    }

    private func deduplicateEvents(_ events: [ScheduledEvent]) -> [ScheduledEvent] {
        var seen: Set<String> = []
        var result: [ScheduledEvent] = []
        for event in events {
            if !seen.contains(event.title) {
                seen.insert(event.title)
                result.append(event)
            }
        }
        return result
    }

    private var infoBannerView: some View {
        let isUncategorized = viewModel.currentEvent == nil
        let groupName = isUncategorized ? "未分类分组" : "\(viewModel.contextTitle)分组"
        
        return Group {
            Text("当前\(isUncategorized ? "无日程" : "日程为" + viewModel.contextTitle)，拍摄的图片将存放在：")
                .foregroundStyle(.white.opacity(0.8))
            + Text(groupName)
                .foregroundStyle(.yellow)
            + Text("，您可通过右上角修改存储路径")
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .stroke(.white.opacity(0.3), lineWidth: 0.5)
                .background(Color.black.opacity(0.6))
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var viewfinder: some View {
        ZStack {
            Color(white: 0.05)

            if viewModel.cameraManager.status == .ready {
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                viewModel.cameraManager.setZoom(factor: currentZoomFactor * value)
                            }
                            .onEnded { value in
                                currentZoomFactor = max(1.0, currentZoomFactor * value)
                                viewModel.cameraManager.setZoom(factor: currentZoomFactor)
                            }
                    )
            } else if viewModel.cameraManager.status == .unauthorized {
                VStack(spacing: 16) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text("需要相机权限才能进行拍记")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("前往设置开启")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.white, in: Capsule())
                    }
                }
            }
            
            // 3x3 Grid
            VStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 0.5)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 0.5)
                Spacer()
            }
            HStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 0.5)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 0.5)
                Spacer()
            }

            // Zoom Indicator
            VStack {
                Spacer()
                Button {
                    currentZoomFactor = 1.0
                    viewModel.cameraManager.setZoom(factor: 1.0)
                } label: {
                    let zoomText = currentZoomFactor == 1.0 ? "1x" : String(format: "%.1fx", currentZoomFactor)
                    Text(zoomText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                }
                .padding(.bottom, 16)
            }
        }
        .aspectRatio(3.0/4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var captureModeSwitcher: some View {
        HStack(spacing: 24) {
            Button("单拍") {
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.captureMode = .single }
            }
            .font(.system(size: 13, weight: viewModel.captureMode == .single ? .bold : .regular))
            .foregroundStyle(viewModel.captureMode == .single ? .yellow : .white.opacity(0.6))

            Button("连拍") {
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.captureMode = .batch }
            }
            .font(.system(size: 13, weight: viewModel.captureMode == .batch ? .bold : .regular))
            .foregroundStyle(viewModel.captureMode == .batch ? .yellow : .white.opacity(0.6))
        }
        .padding(.bottom, 16)
    }

    private var bottomControls: some View {
        HStack {
            // Left: 暂存区
            Button {
                if let latest = viewModel.latestRecord {
                    presentedRecord = latest
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 54, height: 54)
                        .overlay {
                            if let latestRecord = viewModel.latestRecord,
                               let path = latestRecord.localImagePaths.first,
                               let image = LocalImageStore.shared.loadImage(path: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                    if !viewModel.capturedRecords.isEmpty {
                        Text("\(viewModel.capturedRecords.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .frame(width: 80)
            .accessibilityLabel("暂存区")

            Spacer()

            // Center: Shutter
            Button {
                capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 66, height: 66)
                    .scaleEffect(shutterIsPressed ? 0.9 : 1)
                    .overlay {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                    }
            }
            .accessibilityLabel("拍摄")
            
            Spacer()

            // Right: Photos Picker or Finish Batch
            Group {
                if viewModel.captureMode == .batch && !viewModel.batchImagePaths.isEmpty {
                    Button {
                        viewModel.finishBatch()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 54, height: 54)
                            Image(systemName: "checkmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                            
                            Text("\(viewModel.batchImagePaths.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                                .offset(x: 18, y: -18)
                        }
                    }
                    .accessibilityLabel("完成连拍")
                } else {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 54, height: 54)
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel("相册")
                    .onChange(of: selectedItem) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                viewModel.importPhoto(image)
                            }
                            selectedItem = nil
                        }
                    }
                }
            }
            .frame(width: 80)
        }
        .padding(.horizontal, 30)
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
            shutterIsPressed = true
            showsCaptureFlash = true
        }

        viewModel.capturePhoto()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            shutterIsPressed = false
            showsCaptureFlash = false
        }
    }
}

struct CameraControlView: UIViewControllerRepresentable {
    var onCapture: () -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        #if !targetEnvironment(simulator)
        if #available(iOS 18.0, *) {
            let interaction = AVCaptureEventInteraction { event in
                if event.phase == .began {
                    DispatchQueue.main.async {
                        onCapture()
                    }
                }
            }
            vc.view.addInteraction(interaction)
        }
        #endif
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    CaptureView()
}
