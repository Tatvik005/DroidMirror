import SwiftUI
import AppKit

public struct VideoRendererView: NSViewRepresentable {
    public let decoder: H264Decoder
    public let dimensions: (width: Int, height: Int)
    public let onFileDropped: ((URL) -> Void)?

    public init(
        decoder: H264Decoder,
        dimensions: (width: Int, height: Int),
        onFileDropped: ((URL) -> Void)? = nil
    ) {
        self.decoder = decoder
        self.dimensions = dimensions
        self.onFileDropped = onFileDropped
    }

    public func makeNSView(context: Context) -> InputCaptureNSView {
        let view = InputCaptureNSView(frame: .zero)
        decoder.displayLayer = view.displayLayer
        view.videoDimensions = dimensions
        view.onFileDropped = onFileDropped
        return view
    }

    public func updateNSView(_ nsView: InputCaptureNSView, context: Context) {
        nsView.videoDimensions = dimensions
        nsView.onFileDropped = onFileDropped
        if decoder.displayLayer !== nsView.displayLayer {
            decoder.displayLayer = nsView.displayLayer
        }
    }
}
