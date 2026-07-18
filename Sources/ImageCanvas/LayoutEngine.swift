import CoreGraphics
import Foundation

enum LayoutEngine {
    static func nativeSizedItems(
        _ items: [BoardItem],
        nativePixelSizes: [UUID: CGSize]
    ) -> [BoardItem] {
        items.map { item in
            var copy = item
            let size = nativePixelSizes[item.id] ?? item.frame.cgRect.size
            copy.frame = CanvasRect(
                x: 0,
                y: 0,
                width: max(size.width, 1),
                height: max(size.height, 1)
            )
            return copy
        }
    }

    static func nativeTiledLayout(
        items: [BoardItem],
        spacing: CGFloat = 8
    ) -> [BoardItem] {
        guard !items.isEmpty else { return [] }

        let linearSizes = items.map { item in
            sqrt(max(item.frame.width, 1) * max(item.frame.height, 1))
        }.sorted()
        let referenceSize = max(linearSizes[linearSizes.count / 2], 1)
        let normalization = 280 / referenceSize

        let entries = items.map { item in
            let width = max(item.frame.width, 1) * normalization
            let height = max(item.frame.height, 1) * normalization
            return NativeEntry(
                item: item,
                aspectRatio: width / height,
                targetWidth: width,
                targetHeight: height
            )
        }.sorted { lhs, rhs in
            if abs(lhs.targetHeight - rhs.targetHeight) > 0.001 {
                return lhs.targetHeight > rhs.targetHeight
            }
            let lhsArea = lhs.targetWidth * lhs.targetHeight
            let rhsArea = rhs.targetWidth * rhs.targetHeight
            if abs(lhsArea - rhsArea) > 0.001 {
                return lhsArea > rhsArea
            }
            return lhs.item.fileName.localizedStandardCompare(rhs.item.fileName) == .orderedAscending
        }

        let totalArea = entries.reduce(CGFloat(0)) {
            $0 + $1.targetWidth * $1.targetHeight
        }
        let widest = entries.map(\.targetWidth).max() ?? 1
        let baseWidth = max(sqrt(max(totalArea, 1)), widest * 0.6)
        let widthFactors: [CGFloat] = [0.72, 0.84, 0.96, 1.08, 1.22, 1.38, 1.56]

        let candidates = widthFactors.compactMap { factor in
            nativeCandidate(
                entries: entries,
                targetWidth: max(baseWidth * factor, 1),
                spacing: spacing
            )
        }

        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            return center(items: items)
        }
        return center(items: best.items)
    }

    static func cascadingLayout(
        items: [BoardItem],
        spacing: CGFloat = 16
    ) -> [BoardItem] {
        guard !items.isEmpty else { return [] }

        let columnWidth: CGFloat = 260
        let equalized = items.map { item in
            var copy = item
            copy.frame = CanvasRect(
                x: 0,
                y: 0,
                width: columnWidth,
                height: max(1, columnWidth / max(item.aspectRatio, 0.001))
            )
            return copy
        }
        let maximumColumns = min(
            equalized.count,
            max(1, Int(ceil(sqrt(Double(equalized.count)) * 2)))
        )

        var candidates: [CascadingCandidate] = []
        for columnCount in 1...maximumColumns {
            candidates.append(
                cascadingCandidate(
                    items: equalized,
                    columnCount: columnCount,
                    spacing: spacing
                )
            )
        }

        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            return center(items: equalized)
        }
        return center(items: best.items)
    }

    static func picasaLayout(items: [BoardItem], spacing: CGFloat = 8) -> [BoardItem] {
        guard !items.isEmpty else { return [] }

        var sorted = items.sorted {
            let lhsArea = $0.pixelWidth * $0.pixelHeight
            let rhsArea = $1.pixelWidth * $1.pixelHeight
            if lhsArea == rhsArea {
                return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
            return lhsArea > rhsArea
        }

        let targetRowHeight: CGFloat = 280
        let targetWidth = max(820, sqrt(CGFloat(sorted.count)) * 430)
        var arranged: [BoardItem] = []
        var row: [BoardItem] = []
        var rowRatio: CGFloat = 0
        var y: CGFloat = 0

        func emitRow(_ rowItems: [BoardItem], isLast: Bool) {
            guard !rowItems.isEmpty else { return }
            let ratioSum = rowItems.reduce(CGFloat(0)) { $0 + $1.aspectRatio }
            let availableWidth = max(targetWidth - spacing * CGFloat(max(rowItems.count - 1, 0)), 1)
            let rowHeight = isLast
                ? min(targetRowHeight, max(180, availableWidth / max(ratioSum, 0.001)))
                : min(380, max(170, availableWidth / max(ratioSum, 0.001)))
            let rowWidth = ratioSum * rowHeight + spacing * CGFloat(max(rowItems.count - 1, 0))
            var x = -rowWidth / 2

            for var item in rowItems {
                let width = max(1, item.aspectRatio * rowHeight)
                item.frame = CanvasRect(x: x, y: y, width: width, height: rowHeight)
                arranged.append(item)
                x += width + spacing
            }

            y += rowHeight + spacing
        }

        while !sorted.isEmpty {
            let item = sorted.removeFirst()
            row.append(item)
            rowRatio += item.aspectRatio

            if rowRatio * targetRowHeight >= targetWidth {
                emitRow(row, isLast: false)
                row.removeAll()
                rowRatio = 0
            }
        }

        emitRow(row, isLast: true)
        return center(items: arranged)
    }

    static func pinterestLayout(
        items: [BoardItem],
        availableWidth _: CGFloat,
        spacing: CGFloat = 16
    ) -> [BoardItem] {
        cascadingLayout(items: items, spacing: spacing)
    }

    static func appendedLayout(existingItems: [BoardItem], newItems: [BoardItem]) -> [BoardItem] {
        guard !newItems.isEmpty else { return existingItems }
        guard !existingItems.isEmpty else { return picasaLayout(items: newItems) }

        let existingBounds = boundingRect(for: existingItems.map(\.frame.cgRect))
        var arrangedNewItems = picasaLayout(items: newItems)
        let newBounds = boundingRect(for: arrangedNewItems.map(\.frame.cgRect))
        let offsetX = existingBounds.midX - newBounds.midX
        let offsetY = existingBounds.maxY + 80 - newBounds.minY

        arrangedNewItems = arrangedNewItems.map { item in
            var copy = item
            var frame = copy.frame.cgRect
            frame.origin.x += offsetX
            frame.origin.y += offsetY
            copy.frame = CanvasRect(frame)
            return copy
        }

        return existingItems + arrangedNewItems
    }

    static func boundingRect(for rects: [CGRect]) -> CGRect {
        guard var result = rects.first else { return .zero }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    private static func nativeCandidate(
        entries: [NativeEntry],
        targetWidth: CGFloat,
        spacing: CGFloat
    ) -> NativeCandidate? {
        let count = entries.count
        var costs = Array(repeating: CGFloat.infinity, count: count + 1)
        var previous = Array(repeating: -1, count: count + 1)
        costs[0] = 0

        for end in 1...count {
            let earliestStart = max(0, end - 12)
            for start in earliestStart..<end where costs[start].isFinite {
                let metrics = nativeRowMetrics(
                    entries: entries[start..<end],
                    targetWidth: targetWidth,
                    spacing: spacing,
                    isLast: end == count
                )
                let nextCost = costs[start] + metrics.distortion
                if nextCost < costs[end] {
                    costs[end] = nextCost
                    previous[end] = start
                }
            }
        }

        guard previous[count] >= 0 else { return nil }
        var ranges: [Range<Int>] = []
        var end = count
        while end > 0 {
            let start = previous[end]
            guard start >= 0 else { return nil }
            ranges.append(start..<end)
            end = start
        }
        ranges.reverse()

        var arranged: [BoardItem] = []
        var y: CGFloat = 0
        var actualArea: CGFloat = 0
        var boardWidth: CGFloat = 0
        var totalDistortion: CGFloat = 0

        for (rowIndex, range) in ranges.enumerated() {
            let metrics = nativeRowMetrics(
                entries: entries[range],
                targetWidth: targetWidth,
                spacing: spacing,
                isLast: rowIndex == ranges.count - 1
            )
            var x = -metrics.width / 2
            boardWidth = max(boardWidth, metrics.width)
            totalDistortion += metrics.distortion

            for entry in entries[range] {
                var item = entry.item
                let width = max(entry.aspectRatio * metrics.height, 1)
                item.frame = CanvasRect(
                    x: x,
                    y: y,
                    width: width,
                    height: metrics.height
                )
                arranged.append(item)
                actualArea += width * metrics.height
                x += width + spacing
            }
            y += metrics.height
            if rowIndex < ranges.count - 1 {
                y += spacing
            }
        }

        let boardHeight = max(y, 1)
        let aspectPenalty = abs(safeLog(boardWidth / boardHeight))
        let utilization = min(actualArea / max(boardWidth * boardHeight, 1), 1)
        let normalizedDistortion = totalDistortion / CGFloat(max(count, 1))
        let score = normalizedDistortion * 2.4
            + aspectPenalty * 1.5
            + (1 - utilization) * 1.8

        return NativeCandidate(items: arranged, score: score)
    }

    private static func nativeRowMetrics(
        entries: ArraySlice<NativeEntry>,
        targetWidth: CGFloat,
        spacing: CGFloat,
        isLast: Bool
    ) -> NativeRowMetrics {
        let count = entries.count
        let availableWidth = max(
            targetWidth - spacing * CGFloat(max(count - 1, 0)),
            1
        )
        let aspectSum = max(entries.reduce(CGFloat(0)) { $0 + $1.aspectRatio }, 0.001)
        let fillHeight = availableWidth / aspectSum
        let averageTargetLog = entries.reduce(CGFloat(0)) {
            $0 + safeLog($1.targetHeight)
        } / CGFloat(max(count, 1))
        let naturalHeight = safeExp(averageTargetLog)
        let height = isLast ? min(fillHeight, naturalHeight) : fillHeight
        let width = aspectSum * height + spacing * CGFloat(max(count - 1, 0))

        let scaleDistortion = entries.reduce(CGFloat(0)) { result, entry in
            let delta = safeLog(height / max(entry.targetHeight, 0.001))
            return result + delta * delta
        }
        let raggedFraction = isLast
            ? max(0, (targetWidth - width) / max(targetWidth, 1))
            : 0
        let raggedPenalty = raggedFraction * raggedFraction * 0.35

        return NativeRowMetrics(
            height: max(height, 1),
            width: max(width, 1),
            distortion: scaleDistortion + raggedPenalty
        )
    }

    private static func cascadingCandidate(
        items: [BoardItem],
        columnCount: Int,
        spacing: CGFloat
    ) -> CascadingCandidate {
        var columns = Array(repeating: [BoardItem](), count: columnCount)
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for item in items {
            let columnIndex = columnHeights.enumerated().min { lhs, rhs in
                if abs(lhs.element - rhs.element) > 0.001 {
                    return lhs.element < rhs.element
                }
                return lhs.offset < rhs.offset
            }?.offset ?? 0
            columns[columnIndex].append(item)
            columnHeights[columnIndex] += max(item.frame.height, 1) + spacing
        }

        let columnWidths = columns.map { column in
            column.map { max($0.frame.width, 1) }.max() ?? 1
        }
        var x: CGFloat = 0
        var arranged: [BoardItem] = []
        var actualArea: CGFloat = 0

        for index in columns.indices {
            let columnWidth = columnWidths[index]
            var y: CGFloat = 0
            for var item in columns[index] {
                let width = max(item.frame.width, 1)
                let height = max(item.frame.height, 1)
                item.frame = CanvasRect(
                    x: x + (columnWidth - width) / 2,
                    y: y,
                    width: width,
                    height: height
                )
                arranged.append(item)
                actualArea += width * height
                y += height + spacing
            }
            x += columnWidth + spacing
        }

        let bounds = boundingRect(for: arranged.map(\.frame.cgRect))
        let aspectPenalty = abs(safeLog(max(bounds.width, 1) / max(bounds.height, 1)))
        let utilization = min(
            actualArea / max(bounds.width * bounds.height, 1),
            1
        )
        let score = aspectPenalty * 3 + (1 - utilization) * 1.4
        return CascadingCandidate(items: arranged, score: score)
    }

    private static func center(items: [BoardItem]) -> [BoardItem] {
        let bounds = boundingRect(for: items.map(\.frame.cgRect))
        return items.map { item in
            var copy = item
            var frame = copy.frame.cgRect
            frame.origin.x -= bounds.midX
            frame.origin.y -= bounds.midY
            copy.frame = CanvasRect(frame)
            return copy
        }
    }

    private static func safeLog(_ value: CGFloat) -> CGFloat {
        CGFloat(log(Double(max(value, 0.000_001))))
    }

    private static func safeExp(_ value: CGFloat) -> CGFloat {
        CGFloat(exp(Double(value)))
    }

    private struct NativeEntry {
        var item: BoardItem
        var aspectRatio: CGFloat
        var targetWidth: CGFloat
        var targetHeight: CGFloat
    }

    private struct NativeRowMetrics {
        var height: CGFloat
        var width: CGFloat
        var distortion: CGFloat
    }

    private struct NativeCandidate {
        var items: [BoardItem]
        var score: CGFloat
    }

    private struct CascadingCandidate {
        var items: [BoardItem]
        var score: CGFloat
    }
}
