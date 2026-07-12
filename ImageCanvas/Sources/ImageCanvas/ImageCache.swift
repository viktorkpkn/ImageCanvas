import AppKit
import Foundation
import ImageIO

final class ImageCache {
    private let fullImageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let thumbnailQueue = DispatchQueue(label: "local.imagecanvas.thumbnail-cache", qos: .userInitiated)

    init() {
        fullImageCache.countLimit = 80
        thumbnailCache.countLimit = 600
    }

    func image(for item: BoardItem) -> NSImage? {
        guard item.isImage else { return nil }
        let key = item.filePath as NSString
        if let cached = fullImageCache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOfFile: item.filePath) else {
            return nil
        }

        fullImageCache.setObject(image, forKey: key)
        return image
    }

    func displayImage(for item: BoardItem, targetPixelSize: CGFloat, isZooming: Bool) -> NSImage? {
        guard item.isImage else { return nil }
        if targetPixelSize > 2200 {
            return image(for: item)
        }

        let bucket = thumbnailBucket(for: targetPixelSize)
        let key = "\(item.filePath)#\(bucket)" as NSString

        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        if isZooming {
            return cachedThumbnail(for: item)
        }

        guard let image = makeThumbnail(for: item, maxPixelSize: bucket) ?? image(for: item) else {
            return nil
        }

        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func warmThumbnails(for items: [BoardItem]) {
        let items = items
        thumbnailQueue.async { [weak self] in
            guard let self else { return }

            for item in items where item.isImage {
                for bucket in [256, 512, 1024] {
                    let key = "\(item.filePath)#\(bucket)" as NSString
                    if self.thumbnailCache.object(forKey: key) != nil {
                        continue
                    }

                    guard let image = self.makeThumbnail(for: item, maxPixelSize: bucket) else {
                        continue
                    }

                    self.thumbnailCache.setObject(image, forKey: key)
                }
            }
        }
    }

    func clear() {
        fullImageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    private func thumbnailBucket(for targetPixelSize: CGFloat) -> Int {
        switch targetPixelSize {
        case ..<260:
            return 256
        case ..<520:
            return 512
        case ..<1100:
            return 1024
        default:
            return 2048
        }
    }

    private func cachedThumbnail(for item: BoardItem) -> NSImage? {
        for bucket in [1024, 512, 256, 2048] {
            let key = "\(item.filePath)#\(bucket)" as NSString
            if let cached = thumbnailCache.object(forKey: key) {
                return cached
            }
        }

        return nil
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
