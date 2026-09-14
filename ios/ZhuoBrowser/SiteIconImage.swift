import ImageIO
import SwiftUI
import UIKit

enum SiteIconImage {
    static func decode(_ data: Data, maximumPixelSize: CGFloat = 128) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelSize),
                ] as CFDictionary
            )
        else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

struct SiteIconThumbnail: View {
    let image: UIImage
    let size: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}
