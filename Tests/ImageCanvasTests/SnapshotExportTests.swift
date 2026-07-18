import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import ImageCanvas

final class SnapshotExportTests: XCTestCase {
    func testWholeBoardPlanFitsPaddedContentAndCentersIt() throws {
        let plan = try SnapshotGeometry.makePlan(
            logicalSize: CGSize(width: 1_000, height: 600),
            liveScale: 3,
            liveOffset: CGPoint(x: 9, y: 12),
            contentBounds: CGRect(x: 100, y: 200, width: 400, height: 200),
            capturesCurrentView: false,
            resolutionScale: 2
        )

        XCTAssertEqual(plan.pixelWidth, 2_000)
        XCTAssertEqual(plan.pixelHeight, 1_200)
        let rendered = plan.canvasTransform.rect(CGRect(x: 100, y: 200, width: 400, height: 200))
        XCTAssertEqual(rendered.midX, 500, accuracy: 0.001)
        XCTAssertEqual(rendered.midY, 300, accuracy: 0.001)
        XCTAssertGreaterThan(rendered.minX, 0)
        XCTAssertGreaterThan(rendered.minY, 0)
        XCTAssertLessThan(rendered.maxX, 1_000)
        XCTAssertLessThan(rendered.maxY, 600)
    }

    func testCurrentViewPlanPreservesLiveTransform() throws {
        let plan = try SnapshotGeometry.makePlan(
            logicalSize: CGSize(width: 900, height: 620),
            liveScale: 1.5,
            liveOffset: CGPoint(x: 44, y: 55),
            contentBounds: CGRect(x: 0, y: 0, width: 10_000, height: 10_000),
            capturesCurrentView: true,
            resolutionScale: 1
        )

        XCTAssertEqual(plan.canvasTransform, CanvasRenderTransform(scale: 1.5, offset: CGPoint(x: 44, y: 55)))
    }

    func testPlanRequiresConfirmationAboveEightKOnEitherDimension() throws {
        let safe = try SnapshotGeometry.makePlan(
            logicalSize: CGSize(width: 4_096, height: 2_000),
            liveScale: 1,
            liveOffset: .zero,
            contentBounds: nil,
            capturesCurrentView: true,
            resolutionScale: 2
        )
        XCTAssertFalse(safe.requiresLargeExportConfirmation)

        let large = try SnapshotGeometry.makePlan(
            logicalSize: CGSize(width: 4_097, height: 2_000),
            liveScale: 1,
            liveOffset: .zero,
            contentBounds: nil,
            capturesCurrentView: true,
            resolutionScale: 2
        )
        XCTAssertTrue(large.requiresLargeExportConfirmation)
    }

    func testInvalidScaleIsRejected() {
        XCTAssertThrowsError(try SnapshotGeometry.makePlan(
            logicalSize: CGSize(width: 900, height: 620),
            liveScale: 1,
            liveOffset: .zero,
            contentBounds: nil,
            capturesCurrentView: true,
            resolutionScale: 9
        )) { error in
            XCTAssertEqual(error as? SnapshotExportError, .invalidScale)
        }
    }

    func testBoardNameSanitizingDoesNotCreateNestedPaths() {
        XCTAssertEqual(SnapshotFileNaming.sanitizedBoardName("Board/One:Draft"), "Board-One-Draft")
        XCTAssertEqual(SnapshotFileNaming.sanitizedBoardName("  "), "ImageCanvas Snapshot")
    }

    @MainActor
    func testOffscreenRendererProducesOpaqueBlackFrameAndDrawsBoardContent() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCanvas-render-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        guard let sourceContext = CGContext(
            data: nil,
            width: 20,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return XCTFail("Could not create source context")
        }
        sourceContext.setFillColor(NSColor.systemRed.cgColor)
        sourceContext.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        guard let sourceImage = sourceContext.makeImage(),
              let sourceData = NSBitmapImageRep(cgImage: sourceImage)
                .representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode source image")
        }
        try sourceData.write(to: sourceURL, options: .atomic)

        var item = BoardItem(fileURL: sourceURL, pixelWidth: 20, pixelHeight: 10)
        item.frame = CanvasRect(x: 10, y: 10, width: 20, height: 10)
        var board = BoardProject.empty()
        board.items = [item]

        let view = ImageCanvasNSView(frame: CGRect(x: 0, y: 0, width: 100, height: 80))
        view.setBoard(board)
        let plan = try SnapshotGeometry.makePlan(
            logicalSize: view.bounds.size,
            liveScale: 1,
            liveOffset: .zero,
            contentBounds: item.frame.cgRect,
            capturesCurrentView: false,
            resolutionScale: 2
        )
        let pngData = try view.renderSnapshot(plan)

        guard let result = NSBitmapImageRep(data: pngData) else {
            return XCTFail("Could not decode rendered snapshot")
        }
        XCTAssertEqual(result.pixelsWide, 200)
        XCTAssertEqual(result.pixelsHigh, 160)

        let corner = result.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        XCTAssertEqual(corner?.redComponent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(corner?.greenComponent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(corner?.blueComponent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(corner?.alphaComponent ?? -1, 1, accuracy: 0.01)

        let center = result.colorAt(x: 100, y: 80)?.usingColorSpace(.deviceRGB)
        XCTAssertGreaterThan(center?.redComponent ?? 0, 0.8)
        XCTAssertLessThan(center?.greenComponent ?? 1, 0.4)
        XCTAssertLessThan(center?.blueComponent ?? 1, 0.4)
        XCTAssertEqual(center?.alphaComponent ?? -1, 1, accuracy: 0.01)
    }
}
