import AppKit
import AVFoundation
import SwiftUI

public final class InputCaptureNSView: NSView {
    public let displayLayer = AVSampleBufferDisplayLayer()

    public var videoDimensions: (width: Int, height: Int) = (0, 0)
    public var onFileDropped: ((URL) -> Void)?

    private var trackingArea: NSTrackingArea?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer = displayLayer

        registerForDraggedTypes([.fileURL])
    }

    public override var acceptsFirstResponder: Bool {
        return true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    // MARK: - Coordinate Mapping (Preserving Aspect Ratio Letterboxing)

    private func calculateVideoContentRect() -> CGRect {
        return CoordinateMapper.calculateVideoContentRect(viewSize: bounds.size, videoDimensions: videoDimensions)
    }

    private func mapToAndroidPoint(_ locationInView: NSPoint) -> (x: Int32, y: Int32)? {
        return CoordinateMapper.mapPoint(locationInView: locationInView, viewSize: bounds.size, videoDimensions: videoDimensions)
    }

    // MARK: - Mouse Event Handling

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        guard let pt = mapToAndroidPoint(location) else { return }

        ControlInjector.shared.sendTouchEvent(
            action: 0, // ACTION_DOWN
            pointerId: -1,
            x: pt.x,
            y: pt.y,
            screenWidth: UInt16(videoDimensions.width),
            screenHeight: UInt16(videoDimensions.height),
            pressure: 1.0,
            actionButton: 1,
            buttons: 1
        )
    }

    public override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let pt = mapToAndroidPoint(location) else { return }

        ControlInjector.shared.sendTouchEvent(
            action: 2, // ACTION_MOVE
            pointerId: -1,
            x: pt.x,
            y: pt.y,
            screenWidth: UInt16(videoDimensions.width),
            screenHeight: UInt16(videoDimensions.height),
            pressure: 1.0,
            actionButton: 1,
            buttons: 1
        )
    }

    public override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // If release happens outside, map to nearest edge
        let pt = mapToAndroidPoint(location) ?? (x: 0, y: 0)

        ControlInjector.shared.sendTouchEvent(
            action: 1, // ACTION_UP
            pointerId: -1,
            x: pt.x,
            y: pt.y,
            screenWidth: UInt16(videoDimensions.width),
            screenHeight: UInt16(videoDimensions.height),
            pressure: 0.0,
            actionButton: 1,
            buttons: 0
        )
    }

    public override func rightMouseDown(with event: NSEvent) {
        // Android BACK action
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
    }

    public override func otherMouseDown(with event: NSEvent) {
        // Middle mouse button -> Android HOME action
        if event.buttonNumber == 2 {
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.home.rawValue)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let pt = mapToAndroidPoint(location) ?? (x: Int32(videoDimensions.width / 2), y: Int32(videoDimensions.height / 2))

        // Invert deltaY for natural Android gesture
        let hScroll = Float(event.scrollingDeltaX) * 0.1
        let vScroll = Float(-event.scrollingDeltaY) * 0.1

        ControlInjector.shared.sendScrollEvent(
            x: pt.x,
            y: pt.y,
            screenWidth: UInt16(videoDimensions.width),
            screenHeight: UInt16(videoDimensions.height),
            hScroll: hScroll,
            vScroll: vScroll
        )
    }

    // MARK: - Keyboard & Clipboard

    public override func keyDown(with event: NSEvent) {
        // Check for Command key shortcuts
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "c" {
                // Command+C: Trigger copy on Android
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.copy.rawValue)
                return
            } else if key == "v" {
                // Command+V: Paste Mac clipboard into Android
                if let pbText = NSPasteboard.general.string(forType: .string) {
                    ControlInjector.shared.setClipboard(text: pbText, paste: true)
                }
                return
            } else if key == "a" {
                // Command+A: Select all
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.a.rawValue, metaState: 0x1000)
                return
            } else if key == "x" {
                // Command+X: Cut
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.cut.rawValue)
                return
            }
        }

        if let androidKey = KeyMapper.mapMacOSKeyCodeToAndroid(event.keyCode) {
            ControlInjector.shared.sendKeycode(action: 0, keycode: androidKey.rawValue)
        } else if let chars = event.characters, !chars.isEmpty {
            ControlInjector.shared.sendText(chars)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if let androidKey = KeyMapper.mapMacOSKeyCodeToAndroid(event.keyCode) {
            ControlInjector.shared.sendKeycode(action: 1, keycode: androidKey.rawValue)
        }
    }

    // MARK: - Drag and Drop (APK & Files)

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.fileURL.rawValue]) {
            return .copy
        }
        return []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }

        for url in urls {
            onFileDropped?(url)
        }
        return true
    }
}
