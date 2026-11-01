import AppKit
import ImageIO
import SwiftUI

public enum SiteIconImage {
    public static func decode(_ data: Data, maximumPixelSize: CGFloat = 128) -> NSImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(
               source,
               0,
               [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelSize),
               ] as CFDictionary
           ) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        if let nsImage = NSImage(data: data), nsImage.isValid {
            return nsImage
        }
        return nil
    }
}

public struct SiteIconThumbnail: View {
    public let image: NSImage
    public let size: CGFloat
    public var cornerRadius: CGFloat

    public init(image: NSImage, size: CGFloat = 14, cornerRadius: CGFloat = 3) {
        self.image = image
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}
