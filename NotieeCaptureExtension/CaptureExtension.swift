import SwiftUI
import WidgetKit

struct NotieeCaptureEntryView: View {
    var body: some View {
        VStack {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text("Notiee")
                .font(.headline)
        }
    }
}

@main
struct NotieeCaptureExtension: Widget {
    let kind: String = "NotieeCaptureExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            NotieeCaptureEntryView()
        }
        .configurationDisplayName("Notiee 拍记")
        .description("通过相机控制按钮快速启动 Notiee 拍记")
        .supportedFamilies([.accessoryInline])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}
