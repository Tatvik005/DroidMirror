import Foundation
import CoreGraphics

public struct CoordinateMapper {
    public static func calculateVideoContentRect(viewSize: CGSize, videoDimensions: (width: Int, height: Int)) -> CGRect {
        guard videoDimensions.width > 0 && videoDimensions.height > 0 && viewSize.width > 0 && viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let videoAspect = CGFloat(videoDimensions.width) / CGFloat(videoDimensions.height)
        let viewAspect = viewSize.width / max(1, viewSize.height)

        if viewAspect > videoAspect {
            // Pillarbox: black bars left and right
            let contentHeight = viewSize.height
            let contentWidth = contentHeight * videoAspect
            let contentX = (viewSize.width - contentWidth) / 2.0
            return CGRect(x: contentX, y: 0, width: contentWidth, height: contentHeight)
        } else {
            // Letterbox: black bars top and bottom
            let contentWidth = viewSize.width
            let contentHeight = contentWidth / videoAspect
            let contentY = (viewSize.height - contentHeight) / 2.0
            return CGRect(x: 0, y: contentY, width: contentWidth, height: contentHeight)
        }
    }

    public static func mapPoint(
        locationInView: CGPoint,
        viewSize: CGSize,
        videoDimensions: (width: Int, height: Int),
        clamped: Bool = false
    ) -> (x: Int32, y: Int32)? {
        guard videoDimensions.width > 0 && videoDimensions.height > 0 else { return nil }

        let contentRect = calculateVideoContentRect(viewSize: viewSize, videoDimensions: videoDimensions)
        if !clamped && !contentRect.contains(locationInView) {
            return nil
        }

        let normX = (locationInView.x - contentRect.origin.x) / max(1.0, contentRect.width)
        // Flip Y because macOS origin is bottom-left, Android origin is top-left
        let normY = (contentRect.size.height - (locationInView.y - contentRect.origin.y)) / max(1.0, contentRect.height)

        let clampedX = max(0.0, min(1.0, normX))
        let clampedY = max(0.0, min(1.0, normY))

        let androidX = Int32(clampedX * CGFloat(videoDimensions.width))
        let androidY = Int32(clampedY * CGFloat(videoDimensions.height))

        return (
            x: max(0, min(Int32(videoDimensions.width - 1), androidX)),
            y: max(0, min(Int32(videoDimensions.height - 1), androidY))
        )
    }
}
