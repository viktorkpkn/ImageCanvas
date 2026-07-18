import AppKit
import Foundation
import ImageIO

final class ImageCache {
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let thumbnailQueue = DispatchQueue(label: "local.imagecanvas.thumbnail-cache", qos: .userInitiated)
    private let requestLock = NSLock()
    private var pendingThumbnailKeys: Set<String> = []
    private var failedThumbnailKeys: Set<String> = []

    var onThumbnailReady: (() -> Void)?

    init() {
        thumbnailCache.countLimit = 600
    }

    func displayImage(for item: BoardItem, targetPixelSize: CGFloat, isZooming: Bool) -> NSImage? {
        guard item.isImage else { return nil }
        let bucket = thumbnailBucket(for: targetPixelSize)
        let key = "\(item.filePath)#\(bucket)" as NSString

        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        if !isZooming {
            requestThumbnail(for: item, maxPixelSize: bucket)
        }

        return cachedThumbnail(for: item)
    }

    func warmThumbnails(for _: [BoardItem]) {}

    func clear() {
        thumbnailCache.removeAllObjects()
        requestLock.withLock {
            pendingThumbnailKeys.removeAll()
            failedThumbnailKeys.removeAll()
        }
    }

    private func thumbnailBucket(for targetPixelSize: CGFloat) -> Int {
        switch targetPixelSize {
        case ..<260:
            return 256
        case ..<520:
            return 512
        case ..<1100:
            return 1024
        case ..<2200:
            return 2048
        case ..<4400:
            return 4096
        default:
            return 8192
        }
    }

    private func cachedThumbnail(for item: BoardItem) -> NSImage? {
        for bucket in [2048, 1024, 512, 256, 4096, 8192] {
            let key = "\(item.filePath)#\(bucket)" as NSString
            if let cached = thumbnailCache.object(forKey: key) {
                return cached
            }
        }

        return nil
    }

    private func requestThumbnail(for item: BoardItem, maxPixelSize: Int) {
        let key = "\(item.filePath)#\(maxPixelSize)"
        let shouldStart = requestLock.withLock {
            guard !pendingThumbnailKeys.contains(key), !failedThumbnailKeys.contains(key) else {
                return false
            }
            pendingThumbnailKeys.insert(key)
            return true
        }
        guard shouldStart else { return }

        thumbnailQueue.async { [weak self] in
            guard let self else { return }

            let image = self.makeThumbnail(for: item, maxPixelSize: maxPixelSize)
            if let image {
                self.thumbnailCache.setObject(image, forKey: key as NSString)
            }

            self.requestLock.withLock {
                self.pendingThumbnailKeys.remove(key)
                if image == nil {
                    self.failedThumbnailKeys.insert(key)
                }
            }

            guard image != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onThumbnailReady?()
            }
        }
    }

    private func makeThumbnail(for item: BoardItem, maxPixelSize: Int) -> NSImage? {
        let url = URL(fileURLWithPath: item.filePath)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
