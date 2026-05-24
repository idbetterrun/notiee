import SwiftUI

struct HighlightedText: View {
    let text: String
    let query: String
    let font: Font
    let highlightColor: Color
    
    init(text: String, query: String, font: Font = .body, highlightColor: Color = .yellow) {
        self.text = text
        self.query = query
        self.font = font
        self.highlightColor = highlightColor
    }
    
    var body: some View {
        if query.isEmpty {
            Text(text)
                .font(font)
        } else {
            Text(highlightedAttributedString())
                .font(font)
        }
    }
    
    private func highlightedAttributedString() -> AttributedString {
        var attrStr = AttributedString(text)
        if let range = attrStr.range(of: query, options: .caseInsensitive) {
            attrStr[range].backgroundColor = highlightColor.opacity(0.4)
            attrStr[range].foregroundColor = .primary
        }
        return attrStr
    }
}
