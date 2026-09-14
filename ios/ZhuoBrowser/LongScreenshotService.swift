import UIKit
import WebKit

struct LongScreenshotSlice: Equatable {
    let offsetY: CGFloat
    let cropTopRatio: CGFloat
    let cropHeightRatio: CGFloat
}

enum LongScreenshotPlan {
    static let maxScreens = 40
    static let maxOutputPixels: CGFloat = 24_000_000

    static func slices(
        totalHeight: CGFloat,
        viewportHeight: CGFloat,
        maxScreens: Int = maxScreens
    ) -> [LongScreenshotSlice] {
        guard viewportHeight > 0, totalHeight > viewportHeight else {
            return [LongScreenshotSlice(offsetY: 0, cropTopRatio: 0, cropHeightRatio: 1)]
        }

        var result: [LongScreenshotSlice] = []
        let fullScreens = Int(floor(totalHeight / viewportHeight))
        let remainder = totalHeight.truncatingRemainder(dividingBy: viewportHeight)
        for index in 0..<min(fullScreens, maxScreens) {
            result.append(
                LongScreenshotSlice(
                    offsetY: CGFloat(index) * viewportHeight,
                    cropTopRatio: 0,
                    cropHeightRatio: 1
                )
            )
        }
        if remainder > 0, result.count < maxScreens {
            result.append(
                LongScreenshotSlice(
                    offsetY: max(0, totalHeight - viewportHeight),
                    cropTopRatio: (viewportHeight - remainder) / viewportHeight,
                    cropHeightRatio: remainder / viewportHeight
                )
            )
        }
        return result.isEmpty
            ? [LongScreenshotSlice(offsetY: 0, cropTopRatio: 0, cropHeightRatio: 1)]
            : result
    }

    static func snapshotWidthPoints(
        viewportWidth: CGFloat,
        totalHeight: CGFloat,
        viewportHeight: CGFloat,
        displayScale: CGFloat,
        maxScreens: Int = maxScreens,
        maxOutputPixels: CGFloat = maxOutputPixels
    ) -> CGFloat {
        guard viewportWidth > 0, viewportHeight > 0, displayScale > 0 else { return 1 }
        let capturedHeight = min(totalHeight, viewportHeight * CGFloat(maxScreens))
        let aspectRatio = max(1, capturedHeight / viewportWidth)
        let desiredPixelWidth = viewportWidth * displayScale
        let budgetedPixelWidth = sqrt(maxOutputPixels / aspectRatio)
        return max(1, min(desiredPixelWidth, budgetedPixelWidth) / displayScale)
    }
}

struct LongScreenshotResult {
    let image: UIImage
    let wasTruncated: Bool
    let usedViewportFallback: Bool
}

@MainActor
enum LongScreenshotService {
    private static let measureHeightScript = """
    Math.max(
      document.body ? document.body.scrollHeight : 0,
      document.documentElement ? document.documentElement.scrollHeight : 0,
      document.scrollingElement ? document.scrollingElement.scrollHeight : 0,
      window.innerHeight || 0
    )
    """

    private static let prepareScript = """
    (function() {
      var style = document.getElementById('__zhuo_long_shot_style');
      if (!style) {
        style = document.createElement('style');
        style.id = '__zhuo_long_shot_style';
        style.textContent = '::-webkit-scrollbar{display:none!important}html,body{scroll-behavior:auto!important}';
        if (document.head) document.head.appendChild(style);
      }
      var all = document.querySelectorAll('*');
      var vh = window.innerHeight || 1;
      var vw = window.innerWidth || 1;
      for (var i = 0; i < all.length; i++) {
        var element = all[i];
        if (element.id === '__mb-reader' || element.tagName === 'BODY' || element.tagName === 'HTML') continue;
        try {
          var position = window.getComputedStyle(element).position;
          if (position === 'fixed' || position === 'sticky') {
            var rect = element.getBoundingClientRect();
            if (rect.height < vh * 0.35 || rect.width < vw * 0.35) {
              element.setAttribute('data-zhuo-orig-visibility', element.style.visibility || '');
              element.style.setProperty('visibility', 'hidden', 'important');
            }
          }
        } catch (_) {}
      }
      var body = document.body;
      var html = document.documentElement;
      return Math.max(
        body ? body.scrollHeight : 0,
        html ? html.scrollHeight : 0,
        document.scrollingElement ? document.scrollingElement.scrollHeight : 0,
        window.innerHeight || 0
      );
    })()
    """

    private static let restoreScript = """
    (function() {
      var style = document.getElementById('__zhuo_long_shot_style');
      if (style && style.parentNode) style.parentNode.removeChild(style);
      var elements = document.querySelectorAll('[data-zhuo-orig-visibility]');
      for (var i = 0; i < elements.length; i++) {
        var element = elements[i];
        var original = element.getAttribute('data-zhuo-orig-visibility');
        if (original) element.style.visibility = original;
        else element.style.removeProperty('visibility');
        element.removeAttribute('data-zhuo-orig-visibility');
      }
      return 'restored';
    })()
    """

    static func capture(_ webView: WKWebView, isReader: Bool) async throws -> LongScreenshotResult {
        let originalOffset = webView.scrollView.contentOffset
        let viewport = webView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else {
            throw CocoaError(.coderInvalidValue)
        }

        do {
            let scriptHeight = try await webView.evaluateJavaScript(prepareScript) as? NSNumber
            var totalHeight = max(
                viewport.height,
                max(webView.scrollView.contentSize.height, CGFloat(scriptHeight?.doubleValue ?? 0))
            )
            var slices = LongScreenshotPlan.slices(
                totalHeight: totalHeight,
                viewportHeight: viewport.height
            )
            let width = LongScreenshotPlan.snapshotWidthPoints(
                viewportWidth: viewport.width,
                totalHeight: totalHeight,
                viewportHeight: viewport.height,
                displayScale: webView.window?.screen.scale ?? UIScreen.main.scale
            )
            var images: [UIImage] = []
            images.reserveCapacity(LongScreenshotPlan.maxScreens)

            var index = 0
            while index < slices.count {
                let slice = slices[index]
                webView.scrollView.setContentOffset(CGPoint(x: originalOffset.x, y: slice.offsetY), animated: false)
                _ = try? await webView.evaluateJavaScript(
                    "window.scrollTo(0, \(slice.offsetY)); document.scrollingElement && (document.scrollingElement.scrollTop = \(slice.offsetY));"
                )
                try? await Task.sleep(nanoseconds: isReader ? 150_000_000 : 180_000_000)

                let configuration = WKSnapshotConfiguration()
                configuration.rect = webView.bounds
                configuration.snapshotWidth = NSNumber(value: Double(width))
                configuration.afterScreenUpdates = true
                images.append(try await webView.takeSnapshot(configuration: configuration))

                if index < slices.count - 1, index.isMultiple(of: 3) || index == slices.count - 2 {
                    let measured = (try? await webView.evaluateJavaScript(measureHeightScript)) as? NSNumber
                    let expandedHeight = max(
                        webView.scrollView.contentSize.height,
                        CGFloat(measured?.doubleValue ?? 0)
                    )
                    if expandedHeight > totalHeight + 50 {
                        totalHeight = expandedHeight
                        slices = LongScreenshotPlan.slices(
                            totalHeight: totalHeight,
                            viewportHeight: viewport.height
                        )
                    }
                }
                index += 1
            }

            let image = try stitch(slices: slices, images: images)
            await restore(webView, offset: originalOffset)
            return LongScreenshotResult(
                image: image,
                wasTruncated: totalHeight > viewport.height * CGFloat(LongScreenshotPlan.maxScreens),
                usedViewportFallback: false
            )
        } catch {
            await restore(webView, offset: originalOffset)
            let fallback = try await webView.takeSnapshot(configuration: nil)
            return LongScreenshotResult(image: fallback, wasTruncated: false, usedViewportFallback: true)
        }
    }

    private static func restore(_ webView: WKWebView, offset: CGPoint) async {
        _ = try? await webView.evaluateJavaScript(restoreScript)
        webView.scrollView.setContentOffset(offset, animated: false)
        _ = try? await webView.evaluateJavaScript(
            "window.scrollTo(\(offset.x), \(offset.y)); document.scrollingElement && (document.scrollingElement.scrollTop = \(offset.y));"
        )
    }

    private static func stitch(slices: [LongScreenshotSlice], images: [UIImage]) throws -> UIImage {
        guard images.count == slices.count, let first = images.first, first.size.width > 0 else {
            throw CocoaError(.coderInvalidValue)
        }
        if images.count == 1 { return first }

        let outputWidth = first.size.width
        let outputHeight = zip(slices, images).reduce(CGFloat.zero) { partial, pair in
            guard pair.1.size.width > 0 else { return partial }
            let normalizedHeight = pair.1.size.height * outputWidth / pair.1.size.width
            return partial + normalizedHeight * pair.0.cropHeightRatio
        }
        guard outputHeight > 0 else { throw CocoaError(.coderInvalidValue) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = first.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputWidth, height: outputHeight), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
            var outputY: CGFloat = 0
            for (slice, image) in zip(slices, images) {
                let normalizedHeight = image.size.height * outputWidth / image.size.width
                let cropTop = normalizedHeight * slice.cropTopRatio
                let cropHeight = normalizedHeight * slice.cropHeightRatio
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: outputY, width: outputWidth, height: cropHeight))
                image.draw(in: CGRect(x: 0, y: outputY - cropTop, width: outputWidth, height: normalizedHeight))
                context.cgContext.restoreGState()
                outputY += cropHeight
            }
        }
    }
}
