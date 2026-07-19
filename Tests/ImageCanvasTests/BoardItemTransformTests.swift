import CoreGraphics
import Foundation
import XCTest
@testable import ImageCanvas

final class BoardItemTransformTests: XCTestCase {
    func testClockwiseAndCounterclockwiseRotationPreserveCenterAndSwapDimensions() {
        var item = BoardItem(
            fileURL: URL(fileURLWithPath: "/tmp/example.png"),
            pixelWidth: 400,
            pixelHeight: 200
        )
        item.frame = CanvasRect(x: 100, y: 50, width: 400, height: 200)

        let clockwise = BoardItemTransform.rotated(item, clockwise: true)
        let counterclockwise = BoardItemTransform.rotated(item, clockwise: false)

        XCTAssertEqual(clockwise.frame.cgRect.midX, item.frame.cgRect.midX, accuracy: 0.001)
        XCTAssertEqual(clockwise.frame.cgRect.midY, item.frame.cgRect.midY, accuracy: 0.001)
        XCTAssertEqual(clockwise.frame.width, 200, accuracy: 0.001)
        XCTAssertEqual(clockwise.frame.height, 400, accuracy: 0.001)
        XCTAssertEqual(clockwise.rotationDegrees, 90)
        XCTAssertEqual(counterclockwise.rotationDegrees, 270)
    }

    func testFlipsToggleOnlyRequestedAxis() {
        let item = BoardItem(
            fileURL: URL(fileURLWithPath: "/tmp/example.png"),
            pixelWidth: 400,
            pixelHeight: 200
        )

        let horizontal = BoardItemTransform.flipped(item, horizontal: true)
        let vertical = BoardItemTransform.flipped(item, horizontal: false)

        XCTAssertTrue(horizontal.isFlippedHorizontally)
        XCTAssertFalse(horizontal.isFlippedVertically)
        XCTAssertFalse(vertical.isFlippedHorizontally)
        XCTAssertTrue(vertical.isFlippedVertically)
    }

    func testTransformsDoNotChangeTextItems() {
        let item = BoardItem(text: "Caption", at: CGPoint(x: 10, y: 20))

        XCTAssertEqual(BoardItemTransform.rotated(item, clockwise: true), item)
        XCTAssertEqual(BoardItemTransform.flipped(item, horizontal: true), item)
    }
}
