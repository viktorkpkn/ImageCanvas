import CoreGraphics
import Foundation

enum LayoutEngine {
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

    static func pinterestLayout(items: [BoardItem], availableWidth: CGFloat, spacing: CGFloat = 16) -> [BoardItem] {
        guard !items.isEmpty else { return [] }

        let columnWidth: CGFloat = 260
        let columnCount = max(1, Int((max(availableWidth, columnWidth) + spacing) / (columnWidth + spacing)))
        let totalWidth = CGFloat(columnCount) * columnWidth + CGFloat(max(columnCount - 1, 0)) * spacing
        let startX = -totalWidth / 2
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var arranged: [BoardItem] = []

        for var item in items {
            let columnIndex = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let height = max(1, columnWidth / max(item.aspectRatio, 0.001))
            let x = startX + CGFloat(columnIndex) * (columnWidth + spacing)
            let y = columnHeights[columnIndex]
            item.frame = CanvasRect(x: x, y: y, width: columnWidth, height: height)
            arranged.append(item)
            columnHeights[columnIndex] += height + spacing
        }

        return center(items: arranged)
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
}
