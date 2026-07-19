import CoreGraphics
import XCTest
@testable import ImageCanvas

final class FilenameCalloutLayoutTests: XCTestCase {
    func testCalloutFloatsCenteredBelowImage() {
        let frame = FilenameCalloutLayout.frame(
            itemRect: CGRect(x: 200, y: 100, width: 300, height: 180),
            calloutSize: CGSize(width: 220, height: 54),
            canvasBounds: CGRect(x: 0, y: 0, width: 900, height: 700)
        )

        XCTAssertEqual(frame.midX, 350, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 288, accuracy: 0.001)
    }

    func testCalloutClampsToWindowEdges() {
        let left = FilenameCalloutLayout.frame(
            itemRect: CGRect(x: -80, y: 100, width: 40, height: 40),
            calloutSize: CGSize(width: 220, height: 54),
            canvasBounds: CGRect(x: 0, y: 0, width: 500, height: 300)
        )
        let bottom = FilenameCalloutLayout.frame(
            itemRect: CGRect(x: 180, y: 270, width: 100, height: 100),
            calloutSize: CGSize(width: 220, height: 54),
            canvasBounds: CGRect(x: 0, y: 0, width: 500, height: 300)
        )

        XCTAssertEqual(left.minX, 12, accuracy: 0.001)
        XCTAssertEqual(bottom.maxY, 288, accuracy: 0.001)
    }
}
