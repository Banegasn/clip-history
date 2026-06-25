import AppKit
import ImageIO

enum ImageUtil {
    /// Downscale image data to a small PNG thumbnail kept in memory for the list.
    ///
    /// Uses ImageIO (`CGImageSource`) rather than `NSImage.lockFocus()`. lockFocus
    /// relies on a screen graphics context and, in a background/accessory app, can
    /// silently produce a blank or nil bitmap — which is why thumbnails weren't
    /// rendering. ImageIO needs no graphics context and is faster.
    static func thumbnail(from data: Data, maxPixel: Int = 160) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgThumb)
        return rep.representation(using: .png, properties: [:])
    }
}
