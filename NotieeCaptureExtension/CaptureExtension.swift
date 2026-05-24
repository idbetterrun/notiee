import SwiftUI
import WidgetKit

struct LockedCaptureEntryView: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.title)
            .foregroundStyle(.white)
    }
}

@main
struct NotieeCaptureExtension: Widget {
    let kind: String = "NotieeCaptureExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { _ in
            LockedCaptureEntryView()
        }
        .configurationDisplayName("Notiee")
        .description("Quick capture via Camera Control")
        .supportedFamilies([])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) { completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never)) }
}

struct SimpleEntry: TimelineEntry { let date: Date }
