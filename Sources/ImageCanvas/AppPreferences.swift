import CoreGraphics
import Foundation

enum SnapshotPreferences {
    static let scaleKey = "snapshot.resolution-factor"
    static let captureCurrentViewKey = "snapshot.capture-current-view"
    static let defaultScale: CGFloat = 2
    static let scaleRange: ClosedRange<CGFloat> = 0.25...8

    static func validatedScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultScale }
        return min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func currentScale(defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: scaleKey) != nil else { return defaultScale }
        return validatedScale(CGFloat(defaults.double(forKey: scaleKey)))
    }

    static func capturesCurrentView(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: captureCurrentViewKey)
    }
}

enum SnapshotDestination {
    case automaticPictures
    case savePanel
}

struct SnapshotRequest {
    var resolutionScale: CGFloat
    var capturesCurrentView: Bool
    var destination: SnapshotDestination

    static func current(
        destination: SnapshotDestination,
        defaults: UserDefaults = .standard
    ) -> SnapshotRequest {
        SnapshotRequest(
            resolutionScale: SnapshotPreferences.currentScale(defaults: defaults),
            capturesCurrentView: SnapshotPreferences.capturesCurrentView(defaults: defaults),
            destination: destination
        )
    }
}

struct CanvasNotice {
    var message: String
    var fileURL: URL?
    var isError: Bool
}
