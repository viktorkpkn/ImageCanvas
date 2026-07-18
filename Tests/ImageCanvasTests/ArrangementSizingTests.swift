import CoreGraphics
import XCTest
@testable import ImageCanvas

final class ArrangementSizingTests: XCTestCase {
    func testEqualizedTiledMatchesCleanPicasaBaseline() {
        let items = [
            makeItem(name: "B", pixels: CGSize(width: 200, height: 400)),
            makeItem(name: "D", pixels: CGSize(width: 800, height: 200)),
            makeItem(name: "A", pixels: CGSize(width: 400, height: 200)),
            makeItem(name: "C", pixels: CGSize(width: 300, height: 300))
        ]

        let arranged = LayoutEngine.picasaLayout(items: items)

        XCTAssertEqual(arranged.map(\.fileName), ["D", "C", "A", "B"])
        assertFrame(
            arranged[0].frame,
            x: -430,
            y: -232.071_428,
            width: 860,
            height: 215
        )
        assertFrame(
            arranged[1].frame,
            x: -430,
            y: -9.071_428,
            width: 241.142_857,
            height: 241.142_857
        )
        assertFrame(
            arranged[2].frame,
            x: -180.857_143,
            y: -9.071_428,
            width: 482.285_714,
            height: 241.142_857
        )
        assertFrame(
            arranged[3].frame,
            x: 309.428_571,
            y: -9.071_428,
            width: 120.571_429,
            height: 241.142_857
        )
    }

    func testNativeSizingUsesProvidedOrientedPixelSizeAndFallsBackToCurrentFrame() {
        let rotated = makeItem(
            name: "Rotated",
            pixels: CGSize(width: 4_000, height: 3_000),
            frame: CGSize(width: 400, height: 300)
        )
        let unavailable = makeItem(
            name: "Unavailable",
            pixels: CGSize(width: 4_000, height: 3_000),
            frame: CGSize(width: 420, height: 315)
        )

        let sized = LayoutEngine.nativeSizedItems(
            [rotated, unavailable],
            nativePixelSizes: [rotated.id: CGSize(width: 3_000, height: 4_000)]
        )

        XCTAssertEqual(sized[0].frame.width, 3_000)
        XCTAssertEqual(sized[0].frame.height, 4_000)
        XCTAssertEqual(sized[1].frame.width, 420)
        XCTAssertEqual(sized[1].frame.height, 315)
    }

    func testNativeTiledUsesCompactJustifiedRowsWithoutInternalHoles() {
        let sizes = [
            CGSize(width: 1_200, height: 220),
            CGSize(width: 1_000, height: 240),
            CGSize(width: 720, height: 420),
            CGSize(width: 300, height: 760),
            CGSize(width: 360, height: 620),
            CGSize(width: 520, height: 520),
            CGSize(width: 640, height: 360),
            CGSize(width: 420, height: 560),
            CGSize(width: 560, height: 420),
            CGSize(width: 480, height: 480)
        ]
        let items = sizes.enumerated().map { index, size in
            makeItem(name: "Item \(index)", pixels: size, frame: size)
        }

        let arranged = LayoutEngine.nativeTiledLayout(items: items)
        let repeated = LayoutEngine.nativeTiledLayout(items: items)
        let bounds = LayoutEngine.boundingRect(for: arranged.map(\.frame.cgRect))
        let itemArea = arranged.reduce(CGFloat(0)) {
            $0 + $1.frame.width * $1.frame.height
        }
        let outlineAspect = max(bounds.width, bounds.height)
            / max(min(bounds.width, bounds.height), 1)

        XCTAssertEqual(arranged.map(\.id), repeated.map(\.id))
        XCTAssertEqual(arranged.map(\.frame), repeated.map(\.frame))
        XCTAssertLessThanOrEqual(outlineAspect, 1.8)
        XCTAssertGreaterThan(itemArea / (bounds.width * bounds.height), 0.72)

        let distinctAreas = Set(arranged.map {
            Int(($0.frame.width * $0.frame.height).rounded())
        })
        XCTAssertGreaterThan(distinctAreas.count, 2)

        assertNoOverlaps(arranged, spacing: 8)
        assertJustifiedRows(arranged, spacing: 8)
    }

    func testCascadingIsEqualizedCompactAndIndependentOfViewportWidth() {
        let sizes: [CGSize] = [
            CGSize(width: 1_200, height: 240),
            CGSize(width: 300, height: 900),
            CGSize(width: 900, height: 600),
            CGSize(width: 400, height: 700),
            CGSize(width: 1_000, height: 420),
            CGSize(width: 520, height: 760),
            CGSize(width: 800, height: 500),
            CGSize(width: 360, height: 900),
            CGSize(width: 1_100, height: 300),
            CGSize(width: 640, height: 640),
            CGSize(width: 720, height: 480),
            CGSize(width: 450, height: 800)
        ]
        let items = sizes.enumerated().map { index, size in
            makeItem(
                name: "Cascade \(index)",
                pixels: size,
                frame: CGSize(width: size.width / 2, height: size.height / 2)
            )
        }

        let narrow = LayoutEngine.pinterestLayout(items: items, availableWidth: 900)
        let wide = LayoutEngine.pinterestLayout(items: items, availableWidth: 30_000)
        let bounds = LayoutEngine.boundingRect(for: narrow.map(\.frame.cgRect))
        XCTAssertEqual(narrow.map(\.id), wide.map(\.id))
        XCTAssertEqual(narrow.map(\.frame), wide.map(\.frame))
        for item in narrow {
            XCTAssertEqual(item.frame.width, 260, accuracy: 0.001)
        }
        XCTAssertLessThanOrEqual(
            max(bounds.width, bounds.height) / max(min(bounds.width, bounds.height), 1),
            1.8
        )
        assertNoOverlaps(narrow, spacing: 16)
    }

    @MainActor
    func testCanvasEqualizedArrangementPreservesGroupCenterViewportAndOneStepUndo() {
        var first = makeItem(
            name: "First",
            pixels: CGSize(width: 1_000, height: 500),
            frame: CGSize(width: 500, height: 250)
        )
        first.frame = CanvasRect(x: 100, y: 200, width: 500, height: 250)
        var second = makeItem(
            name: "Second",
            pixels: CGSize(width: 400, height: 1_200),
            frame: CGSize(width: 120, height: 360)
        )
        second.frame = CanvasRect(x: 800, y: 500, width: 120, height: 360)

        var board = BoardProject.empty()
        board.items = [first, second]
        board.viewport = ViewportState(scale: 1.4, offsetX: 72, offsetY: 96)
        let originalFrames = board.items.map(\.frame)
        let originalBounds = LayoutEngine.boundingRect(for: board.items.map(\.frame.cgRect))
        let baseline = LayoutEngine.picasaLayout(items: board.items)
        var changedBoard: BoardProject?

        let view = ImageCanvasNSView(frame: CGRect(x: 0, y: 0, width: 1_100, height: 700))
        view.configure(
            imageCache: ImageCache(),
            isDrawingModeEnabled: false,
            isTextModeEnabled: false,
            areControlsVisible: true,
            drawingColor: .systemYellow,
            onBoardChanged: { changedBoard = $0 },
            onAddFiles: { _ in },
            onToggleChrome: {},
            onDrawingModeChanged: { _ in },
            onTextModeChanged: { _ in },
            onCanvasInteraction: {}
        )
        view.setBoard(board)

        NotificationCenter.default.post(name: .imageCanvasArrangePicasa, object: nil)

        guard let arrangedBoard = changedBoard else {
            return XCTFail("Arrangement did not commit")
        }
        let arrangedBounds = LayoutEngine.boundingRect(for: arrangedBoard.items.map(\.frame.cgRect))
        XCTAssertEqual(arrangedBounds.midX, originalBounds.midX, accuracy: 0.001)
        XCTAssertEqual(arrangedBounds.midY, originalBounds.midY, accuracy: 0.001)
        XCTAssertEqual(arrangedBoard.viewport, board.viewport)

        let expectedSizes = Dictionary(uniqueKeysWithValues: baseline.map {
            ($0.id, $0.frame.cgRect.size)
        })
        for item in arrangedBoard.items {
            XCTAssertEqual(item.frame.cgRect.size, expectedSizes[item.id])
        }

        NotificationCenter.default.post(name: .imageCanvasUndo, object: nil)
        XCTAssertEqual(changedBoard?.items.map(\.frame), originalFrames)
        XCTAssertEqual(changedBoard?.viewport, board.viewport)
    }

    private func assertFrame(
        _ frame: CanvasRect,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.x, x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(frame.y, y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(frame.width, width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(frame.height, height, accuracy: 0.001, file: file, line: line)
    }

    private func assertNoOverlaps(
        _ items: [BoardItem],
        spacing: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for firstIndex in items.indices {
            for secondIndex in items.indices where secondIndex > firstIndex {
                XCTAssertFalse(
                    items[firstIndex].frame.cgRect
                        .insetBy(dx: -(spacing / 2 - 0.1), dy: -(spacing / 2 - 0.1))
                        .intersects(items[secondIndex].frame.cgRect),
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertJustifiedRows(
        _ items: [BoardItem],
        spacing: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var rows: [[BoardItem]] = []
        for item in items.sorted(by: { $0.frame.y < $1.frame.y }) {
            if let index = rows.firstIndex(where: {
                abs(($0.first?.frame.y ?? 0) - item.frame.y) < 0.001
            }) {
                rows[index].append(item)
            } else {
                rows.append([item])
            }
        }

        XCTAssertGreaterThan(rows.count, 1, file: file, line: line)
        for row in rows {
            let ordered = row.sorted { $0.frame.x < $1.frame.x }
            for item in ordered.dropFirst() {
                XCTAssertEqual(item.frame.height, ordered[0].frame.height, accuracy: 0.001, file: file, line: line)
            }
            for index in 1..<ordered.count {
                XCTAssertEqual(
                    ordered[index].frame.x - (ordered[index - 1].frame.x + ordered[index - 1].frame.width),
                    spacing,
                    accuracy: 0.001,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func makeItem(
        name: String,
        pixels: CGSize,
        frame: CGSize? = nil
    ) -> BoardItem {
        var item = BoardItem(
            fileURL: URL(fileURLWithPath: "/tmp/\(name).png"),
            pixelWidth: pixels.width,
            pixelHeight: pixels.height
        )
        item.fileName = name
        let displayedSize = frame ?? pixels
        item.frame = CanvasRect(
            x: 0,
            y: 0,
            width: displayedSize.width,
            height: displayedSize.height
        )
        return item
    }
}
