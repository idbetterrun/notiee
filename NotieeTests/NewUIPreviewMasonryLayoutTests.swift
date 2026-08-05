import CoreGraphics
import XCTest
@testable import Notiee

final class NewUIPreviewMasonryLayoutTests: XCTestCase {
    func testPlacesEachItemInCurrentShorterColumn() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: [
                CGSize(width: 10, height: 120),
                CGSize(width: 10, height: 60),
                CGSize(width: 10, height: 40),
                CGSize(width: 10, height: 30)
            ],
            containerWidth: 212,
            columns: 2,
            spacing: 12
        )

        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 100, height: 120))
        XCTAssertEqual(frames[1], CGRect(x: 112, y: 0, width: 100, height: 60))
        XCTAssertEqual(frames[2], CGRect(x: 112, y: 72, width: 100, height: 40))
        XCTAssertEqual(frames[3], CGRect(x: 112, y: 124, width: 100, height: 30))
    }

    func testEqualHeightColumnsPreferLeftmostColumn() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: Array(repeating: CGSize(width: 1, height: 40), count: 3),
            containerWidth: 210,
            columns: 2,
            spacing: 10
        )

        XCTAssertEqual(frames.map(\.minX), [0, 110, 0])
        XCTAssertEqual(frames[2].minY, 50)
    }

    func testFramesRemainInSourceOrder() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: [
                CGSize(width: 1, height: 100),
                CGSize(width: 1, height: 20),
                CGSize(width: 1, height: 30)
            ],
            containerWidth: 206,
            columns: 2,
            spacing: 6
        )

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].origin, CGPoint(x: 0, y: 0))
        XCTAssertEqual(frames[1].origin, CGPoint(x: 106, y: 0))
        XCTAssertEqual(frames[2].origin, CGPoint(x: 106, y: 26))
    }

    func testSingleColumnUsesFullWidthAndVerticalSpacing() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: [
                CGSize(width: 20, height: 30),
                CGSize(width: 20, height: 50)
            ],
            containerWidth: 180,
            columns: 1,
            spacing: 12
        )

        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 180, height: 30))
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 42, width: 180, height: 50))
    }

    func testContentHeightIsTallestColumnWithoutTrailingSpacing() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: [
                CGSize(width: 1, height: 100),
                CGSize(width: 1, height: 40),
                CGSize(width: 1, height: 30)
            ],
            containerWidth: 220,
            columns: 2,
            spacing: 12
        )

        XCTAssertEqual(NewUIPreviewMasonryGeometry.contentHeight(for: frames), 100)
    }

    func testEmptyInputProducesNoFramesOrHeight() {
        let frames = NewUIPreviewMasonryGeometry.frames(
            itemSizes: [],
            containerWidth: 220,
            columns: 2,
            spacing: 12
        )

        XCTAssertTrue(frames.isEmpty)
        XCTAssertEqual(NewUIPreviewMasonryGeometry.contentHeight(for: frames), 0)
    }
}
