import CoreGraphics
import SwiftUI
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

    func testColumnWidthUsesTheSameContractAcrossSupportedPhoneWidths() {
        XCTAssertEqual(
            NewUIPreviewMasonryGeometry.columnWidth(containerWidth: 288, columns: 2, spacing: 12),
            138
        )
        XCTAssertEqual(
            NewUIPreviewMasonryGeometry.columnWidth(containerWidth: 343, columns: 2, spacing: 12),
            165.5
        )
        XCTAssertEqual(
            NewUIPreviewMasonryGeometry.columnWidth(containerWidth: 396, columns: 2, spacing: 12),
            192
        )
        XCTAssertEqual(
            NewUIPreviewMasonryGeometry.columnWidth(containerWidth: 396, columns: 1, spacing: 12),
            396
        )
    }

    func testMediaTemplatesStayInsideTheirAvailableWidth() {
        let availableWidths: [CGFloat] = [114, 141.5, 168, 372]

        for width in availableWidths {
            for count in 0...6 {
                let layout = NewUIPreviewRecordMediaGeometry.layout(
                    media: mediaFixtures(count: count),
                    width: width,
                    spacing: 3
                )

                XCTAssertEqual(layout.frames.count, min(count, 4), "width: \(width), count: \(count)")
                XCTAssertEqual(layout.height == 0, count == 0, "width: \(width), count: \(count)")

                for frame in layout.frames {
                    XCTAssertGreaterThanOrEqual(frame.minX, 0, "width: \(width), count: \(count)")
                    XCTAssertGreaterThanOrEqual(frame.minY, 0, "width: \(width), count: \(count)")
                    XCTAssertLessThanOrEqual(frame.maxX, width + 0.001, "width: \(width), count: \(count)")
                    XCTAssertLessThanOrEqual(
                        frame.maxY,
                        layout.height + 0.001,
                        "width: \(width), count: \(count)"
                    )
                }

                for firstIndex in layout.frames.indices {
                    for secondIndex in layout.frames.indices where secondIndex > firstIndex {
                        XCTAssertFalse(
                            layout.frames[firstIndex].intersects(layout.frames[secondIndex]),
                            "width: \(width), count: \(count), frames: \(firstIndex), \(secondIndex)"
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func testEveryRecordCardVariantAcceptsAnExplicitColumnWidth() throws {
        let cardWidths: [CGFloat] = [138, 165.5, 192, 396]
        let fixtures = NewUIPreviewFixtures.records
        let variants = try [
            XCTUnwrap(
                fixtures.first {
                    $0.record.processingState == .completed && !$0.record.isEncrypted && $0.media.count == 6
                }
            ),
            XCTUnwrap(fixtures.first { $0.record.processingState == .failed }),
            XCTUnwrap(fixtures.first { $0.record.processingState == .pending }),
            XCTUnwrap(fixtures.first { $0.record.processingState == .processing }),
            XCTUnwrap(fixtures.first { $0.record.isEncrypted })
        ]

        for cardWidth in cardWidths {
            for fixture in variants {
                let view = NewUIPreviewRecordCard(
                    fixture: fixture,
                    cardWidth: cardWidth,
                    action: {}
                )
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                let host = UIHostingController(rootView: view)
                let size = host.sizeThatFits(in: CGSize(width: cardWidth, height: 2_000))

                XCTAssertEqual(size.width, cardWidth, accuracy: 0.5, "record: \(fixture.id)")
                XCTAssertGreaterThan(size.height, 0, "record: \(fixture.id)")
                XCTAssertTrue(size.height.isFinite, "record: \(fixture.id)")
            }
        }
    }

    private func mediaFixtures(count: Int) -> [NewUIPreviewMedia] {
        (0..<count).map { index in
            NewUIPreviewMedia(
                id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", index + 1))!,
                imageName: "NewUIPreviewPhoto01",
                pixelSize: index == 0
                    ? CGSize(width: 900, height: 1_200)
                    : CGSize(width: 1_200, height: 900)
            )
        }
    }
}
