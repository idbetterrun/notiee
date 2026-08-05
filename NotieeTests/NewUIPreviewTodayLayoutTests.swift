import SwiftUI
import UIKit
import XCTest
@testable import Notiee

@MainActor
final class NewUIPreviewTodayLayoutTests: XCTestCase {
    func testTodayEyebrowAndFixedGeometryRemainStable() {
        XCTAssertEqual(NewUIPreviewTodayLayout.eyebrowTitle, "Today")
        XCTAssertEqual(NewUIPreviewTodayLayout.itemHeight, 68)
        XCTAssertEqual(NewUIPreviewTodayLayout.itemSpacing, 12)
    }

    func testFittingItemCountUsesEveryCompleteAvailableRowWithoutAThreeItemCap() {
        let fixedContentHeight: CGFloat = 320

        for count in 1...5 {
            let rowsHeight = CGFloat(count) * NewUIPreviewTodayLayout.itemHeight
                + CGFloat(count - 1) * NewUIPreviewTodayLayout.itemSpacing
            XCTAssertEqual(
                NewUIPreviewTodayLayout.fittingItemCount(
                    availableHeight: fixedContentHeight + rowsHeight,
                    fixedContentHeight: fixedContentHeight,
                    itemCount: 8
                ),
                count
            )
        }
    }

    func testFittingItemCountClampsToDataAndAddsOneItemPerCompleteUnit() {
        let fixedContentHeight: CGFloat = 300
        let oneRowHeight = NewUIPreviewTodayLayout.itemHeight

        XCTAssertEqual(
            NewUIPreviewTodayLayout.fittingItemCount(
                availableHeight: fixedContentHeight + oneRowHeight,
                fixedContentHeight: fixedContentHeight,
                itemCount: 6
            ),
            1
        )
        XCTAssertEqual(
            NewUIPreviewTodayLayout.fittingItemCount(
                availableHeight: fixedContentHeight + oneRowHeight
                    + NewUIPreviewTodayLayout.itemHeight
                    + NewUIPreviewTodayLayout.itemSpacing,
                fixedContentHeight: fixedContentHeight,
                itemCount: 6
            ),
            2
        )
        XCTAssertEqual(
            NewUIPreviewTodayLayout.fittingItemCount(
                availableHeight: fixedContentHeight + 600,
                fixedContentHeight: fixedContentHeight,
                itemCount: 2
            ),
            2
        )
        XCTAssertEqual(
            NewUIPreviewTodayLayout.fittingItemCount(
                availableHeight: fixedContentHeight,
                fixedContentHeight: fixedContentHeight,
                itemCount: 0
            ),
            0
        )
    }

    func testLargerMeasuredContentReducesTheCountWithoutChangingRowGeometry() {
        let availableHeight: CGFloat = 700
        let regularFixedHeight: CGFloat = 320
        let accessibilityFixedHeight = regularFixedHeight
            + NewUIPreviewTodayLayout.itemHeight
            + NewUIPreviewTodayLayout.itemSpacing

        let regularCount = NewUIPreviewTodayLayout.fittingItemCount(
            availableHeight: availableHeight,
            fixedContentHeight: regularFixedHeight,
            itemCount: 8
        )
        let accessibilityCount = NewUIPreviewTodayLayout.fittingItemCount(
            availableHeight: availableHeight,
            fixedContentHeight: accessibilityFixedHeight,
            itemCount: 8
        )

        XCTAssertEqual(regularCount, accessibilityCount + 1)
    }

    func testEveryTodayItemStyleUsesTheFullFixedStripSize() {
        let contentWidths: [CGFloat] = [280, 335, 388]
        let styles: [NewUIPreviewTodayItemStyle] = [
            .record(imageName: nil),
            .todo,
            .schedule(isNow: true),
            .schedule(isNow: false)
        ]

        for width in contentWidths {
            for style in styles {
                assertCardSize(width: width, style: style, dynamicTypeSize: .large)
                assertCardSize(width: width, style: style, dynamicTypeSize: .accessibility3)
            }
        }
    }

    func testViewAllPillKeepsIntrinsicWidthAndFixedHeight() {
        let pill = NewUIPreviewViewAllButton(section: .records, action: {})
        let pillHost = UIHostingController(rootView: pill)
        let pillSize = pillHost.sizeThatFits(in: CGSize(width: 335, height: 200))

        let view = HStack {
            pill
            Spacer(minLength: 0)
        }
        .frame(width: 335, alignment: .leading)

        let host = UIHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: 335, height: 200))

        XCTAssertGreaterThan(pillSize.width, 44)
        XCTAssertLessThan(pillSize.width, 335)
        XCTAssertEqual(pillSize.height, 44, accuracy: 0.5)
        XCTAssertEqual(size.width, 335, accuracy: 0.5)
        XCTAssertEqual(size.height, 44, accuracy: 0.5)
    }

    func testRecordsFilterWhiteMaskOnlyAppliesToUnselectedButtons() {
        XCTAssertEqual(
            NewUIPreviewRecordsFilterAppearance.whiteMaskOpacity(
                isSelected: true,
                colorScheme: .light,
                reduceTransparency: false
            ),
            0
        )
        XCTAssertEqual(
            NewUIPreviewRecordsFilterAppearance.whiteMaskOpacity(
                isSelected: false,
                colorScheme: .light,
                reduceTransparency: false
            ),
            0.46
        )
        XCTAssertEqual(
            NewUIPreviewRecordsFilterAppearance.whiteMaskOpacity(
                isSelected: false,
                colorScheme: .dark,
                reduceTransparency: false
            ),
            0.12
        )
        XCTAssertGreaterThan(
            NewUIPreviewRecordsFilterAppearance.whiteMaskOpacity(
                isSelected: false,
                colorScheme: .light,
                reduceTransparency: true
            ),
            0.46
        )
    }

    private func assertCardSize(
        width: CGFloat,
        style: NewUIPreviewTodayItemStyle,
        dynamicTypeSize: DynamicTypeSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let view = NewUIPreviewTodayItemCard(
            title: "一条足够长的测试标题，用于验证固定长条不会改变外框",
            detail: "辅助文字同样保持单行并在需要时截断",
            style: style
        )
        .frame(width: width)
        .environment(\.dynamicTypeSize, dynamicTypeSize)

        let host = UIHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: width, height: 400))

        XCTAssertEqual(size.width, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(
            size.height,
            NewUIPreviewTodayLayout.itemHeight,
            accuracy: 0.5,
            file: file,
            line: line
        )
    }
}
