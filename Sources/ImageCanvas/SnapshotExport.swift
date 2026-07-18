import CoreGraphics
import Foundation

enum SnapshotExportError: LocalizedError, Equatable {
    case invalidViewport
    case invalidScale
    case dimensionsOverflow
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidViewport:
            "The canvas does not have a valid snapshot size."
        case .invalidScale:
            "The snapshot resolution factor is invalid."
        case .dimensionsOverflow:
            "The requested snapshot dimensions are too large."
        case .bitmapCreationFailed:
            "ImageCanvas could not allocate the snapshot bitmap."
        case .pngEncodingFailed:
            "ImageCanvas could not encode the snapshot as PNG."
        }
    }
}

struct CanvasRenderTransform: Equatable {
    var scale: CGFloat
    var offset: CGPoint

    func point(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scale + offset.x,
            y: canvasPoint.y * scale + offset.y
        )
    }

    func rect(_ canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.minX * scale + offset.x,
            y: canvasRect.minY * scale + offset.y,
            width: canvasRect.width * scale,
            height: canvasRect.height * scale
        )
    }
}

struct SnapshotRenderPlan: Equatable {
    var logicalSize: CGSize
    var pixelWidth: Int
    var pixelHeight: Int
    var resolutionScale: CGFloat
    var canvasTransform: CanvasRenderTransform

    var requiresLargeExportConfirmation: Bool {
        pixelWidth > 8_192 || pixelHeight > 8_192
    }

    var estimatedRawMegabytes: Int? {
        let (rowBytes, rowOverflow) = pixelWidth.multipliedReportingOverflow(by: 4)
        guard !rowOverflow else { return nil }
        let (totalBytes, totalOverflow) = rowBytes.multipliedReportingOverflow(by: pixelHeight)
        guard !totalOverflow else { return nil }
        return Int(ceil(Double(totalBytes) / 1_048_576))
    }
}

enum SnapshotGeometry {
    static func makePlan(
        logicalSize: CGSize,
        liveScale: CGFloat,
        liveOffset: CGPoint,
        contentBounds: CGRect?,
        capturesCurrentView: Bool,
        resolutionScale: CGFloat
    ) throws -> SnapshotRenderPlan {
        guard logicalSize.width.isFinite,
              logicalSize.height.isFinite,
              logicalSize.width > 0,
              logicalSize.height > 0 else {
            throw SnapshotExportError.invalidViewport
        }

        guard resolutionScale.isFinite,
              SnapshotPreferences.scaleRange.contains(resolutionScale) else {
            throw SnapshotExportError.invalidScale
        }

        let scaledWidth = ceil(logicalSize.width * resolutionScale)
        let scaledHeight = ceil(logicalSize.height * resolutionScale)
        guard scaledWidth.isFinite,
              scaledHeight.isFinite,
              scaledWidth > 0,
              scaledHeight > 0,
              scaledWidth <= CGFloat(Int.max),
              scaledHeight <= CGFloat(Int.max) else {
            throw SnapshotExportError.dimensionsOverflow
        }

        let transform: CanvasRenderTransform
        if capturesCurrentView || contentBounds == nil || contentBounds?.isNull == true {
            transform = CanvasRenderTransform(
                scale: max(liveScale, 0.02),
                offset: liveOffset
            )
        } else if let contentBounds {
            let longestSide = max(max(contentBounds.width, contentBounds.height), 1)
            let padding = max(32, longestSide * 0.05)
            let paddedBounds = contentBounds.insetBy(dx: -padding, dy: -padding)
            let fittedScale = min(
                logicalSize.width / max(paddedBounds.width, 1),
                logicalSize.height / max(paddedBounds.height, 1)
            )
            transform = CanvasRenderTransform(
                scale: max(fittedScale, 0.000_001),
                offset: CGPoint(
                    x: logicalSize.width / 2 - paddedBounds.midX * fittedScale,
                    y: logicalSize.height / 2 - paddedBounds.midY * fittedScale
                )
            )
        } else {
            throw SnapshotExportError.invalidViewport
        }

        return SnapshotRenderPlan(
            logicalSize: logicalSize,
            pixelWidth: Int(scaledWidth),
            pixelHeight: Int(scaledHeight),
            resolutionScale: resolutionScale,
            canvasTransform: transform
        )
    }
}

enum SnapshotFileNaming {
    static func picturesDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
    }

    static func sanitizedBoardName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let replaced = name.components(separatedBy: forbidden).joined(separator: "-")
        let collapsed = replaced
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return collapsed.isEmpty ? "ImageCanvas Snapshot" : collapsed
    }

    static func uniqueURL(
        boardName: String,
        directory: URL,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let baseName = "\(sanitizedBoardName(boardName)) — \(formatter.string(from: date))"
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }
        return candidate
    }
}
