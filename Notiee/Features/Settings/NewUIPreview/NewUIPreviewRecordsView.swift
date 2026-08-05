import SwiftUI

struct NewUIPreviewRecordsView: View {
    @EnvironmentObject private var previewState: NewUIPreviewState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("记录")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.newUIPreviewPrimary)

                searchField

                if previewState.filteredRecordFixtures.isEmpty {
                    emptyState
                } else {
                    NewUIPreviewMasonryLayout(columns: columnCount, spacing: 12) {
                        ForEach(previewState.filteredRecordFixtures) { fixture in
                            NewUIPreviewRecordCard(fixture: fixture) {
                                previewState.openRecord(fixture.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.2), value: previewState.filteredRecordFixtures.map(\.id))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 124)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color.newUIPreviewBackground)
        .accessibilityIdentifier("new-ui-preview-records")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.newUIPreviewSecondary)
                .accessibilityHidden(true)

            TextField("搜索标题和摘要", text: $previewState.recordsSearchQuery)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)

            if !previewState.recordsSearchQuery.isEmpty {
                Button {
                    previewState.recordsSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.newUIPreviewSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, previewState.recordsSearchQuery.isEmpty ? 16 : 4)
        .frame(minHeight: 52)
        .contentShape(Capsule())
        .newUIPreviewGlass(in: Capsule(), interactive: true)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: previewState.recordsSearchQuery.isEmpty ? "tray" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.newUIPreviewSecondary)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(previewState.recordsSearchQuery.isEmpty ? "还没有记录" : "没有匹配的记录"))
                .font(.headline)
                .foregroundStyle(Color.newUIPreviewPrimary)

            if !previewState.recordsSearchQuery.isEmpty {
                Text("尝试搜索标题或摘要中的其他词语")
                    .font(.subheadline)
                    .foregroundStyle(Color.newUIPreviewSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }
}
