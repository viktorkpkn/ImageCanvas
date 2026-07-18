import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import ImageCanvas

final class ImageCacheTests: XCTestCase {
    @MainActor
    func testDisplayRequestCompletesAsynchronouslyAndNotifiesWhenReady() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCanvas-cache-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        guard let context = CGContext(
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
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        guard let sourceImage = context.makeImage(),
              let sourceData = NSBitmapImageRep(cgImage: sourceImage)
                .representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode source image")
        }
        try sourceData.write(to: sourceURL, options: .atomic)

        let item = BoardItem(fileURL: sourceURL, pixelWidth: 20, pixelHeight: 10)
        let cache = ImageCache()
        let ready = expectation(description: "thumbnail decoded")
        cache.onThumbnailReady = {
            ready.fulfill()
        }

        XCTAssertNil(cache.displayImage(for: item, targetPixelSize: 128, isZooming: false))
        wait(for: [ready], timeout: 2)
        XCTAssertNotNil(cache.displayImage(for: item, targetPixelSize: 128, isZooming: false))
    }
}
