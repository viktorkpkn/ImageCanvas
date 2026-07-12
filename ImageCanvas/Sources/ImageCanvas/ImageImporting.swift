import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageImporting {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif"
    ]

    static func imageURLs(from urls: [URL]) -> [URL] {
        urls
            .filter { isSupportedImageURL($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func imageURLs(in folderURL: URL, includeSubfolders: Bool) -> [URL] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .nameKey]

        if includeSubfolders {
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            return enumerator.compactMap { element in
                guard let url = element as? URL else { return nil }
                return isSupportedImageURL(url) ? url : nil
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return imageURLs(from: children)
    }

    static func metadata(for url: URL) -> ImageMetadata? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat
            ?? (properties[kCGImagePropertyPixelWidth] as? NSNumber).map { CGFloat(truncating: $0) }
        let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
            ?? (properties[kCGImagePropertyPixelHeight] as? NSNumber).map { CGFloat(truncating: $0) }

        guard let width, let height else {
            return nil
        }

        return ImageMetadata(pixelWidth: max(width, 1), pixelHeight: max(height, 1))
    }

    private static func isSupportedImageURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

enum ImportPanel {
    static func pickImages() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Add Images"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        return panel.runModal() == .OK ? panel.urls : nil
    }

    static func pickFolder() -> (url: URL, includeSubfolders: Bool)? {
        let panel = NSOpenPanel()
        panel.title = "Open Image Folder"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        let checkbox = NSButton(checkboxWithTitle: "Include Subfolders", target: nil, action: nil)
        checkbox.state = .off
        checkbox.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        panel.accessoryView = checkbox

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return (url, checkbox.state == .on)
    }
}
