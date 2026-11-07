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

    private func mapToAndroidPoint(_ locationInView: NSPoint, clamped: Bool = false) -> (x: Int32, y: Int32)? {
        return CoordinateMapper.mapPoint(locationInView: locationInView, viewSize: bounds.size, videoDimensions: videoDimensions, clamped: clamped)
    }

    // MARK: - Mouse Event Handling

    private var initialMouseDownPoint: NSPoint?
    private var lastValidAndroidPoint: (x: Int32, y: Int32)?
    private var isDragging: Bool = false

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        // 1. If Command key is held, drag the floating window natively from anywhere
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        guard let pt = mapToAndroidPoint(location, clamped: false) else {
            // Clicks outside video content are ignored; window move is exclusively ⌘+Drag
            return
        }

        initialMouseDownPoint = location
        lastValidAndroidPoint = pt
        isDragging = false

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
        // Enable clamped tracking so dragging scrolls and sliders smoothly right up to the display borders
        guard let pt = mapToAndroidPoint(location, clamped: true) else { return }

        // Suppress micro-jitter (<2.0 pt) on stationary clicks to avoid accidental micro-drags
        if !isDragging, let down = initialMouseDownPoint {
            let dx = location.x - down.x
            let dy = location.y - down.y
            if (dx * dx + dy * dy) < 4.0 {
                return
            }
            isDragging = true
        }

        lastValidAndroidPoint = pt

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
        // Clamp touch release to display boundary instead of snapping to top-left (0, 0)
        let pt = mapToAndroidPoint(location, clamped: true) ?? lastValidAndroidPoint ?? (x: Int32(videoDimensions.width / 2), y: Int32(videoDimensions.height / 2))

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

        initialMouseDownPoint = nil
        lastValidAndroidPoint = nil
        isDragging = false
    }

    public override func rightMouseDown(with event: NSEvent) {
        // Right-Click -> Android BACK action
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
    }

    public override func otherMouseDown(with event: NSEvent) {
        // Extended mouse navigation:
        // Button 2 (Middle click) -> Android HOME
        // Button 3 (Mouse side Back) -> Android BACK
        // Button 4 (Mouse side Forward) -> Android RECENTS / APP SWITCHER
        switch event.buttonNumber {
        case 2:
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.home.rawValue)
        case 3:
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
        case 4:
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.appSwitch.rawValue)
        default:
            break
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let pt = mapToAndroidPoint(location, clamped: true) ?? (x: Int32(videoDimensions.width / 2), y: Int32(videoDimensions.height / 2))

        // Differentiate smooth macOS trackpad deltas from notched mouse wheel ticks
        let factor: Float = event.hasPreciseScrollingDeltas ? 0.04 : 0.25
        let hScroll = Float(event.scrollingDeltaX) * factor
        let vScroll = Float(-event.scrollingDeltaY) * factor

        // Filter out sub-pixel trackpad jitter
        if abs(hScroll) < 0.005 && abs(vScroll) < 0.005 {
            return
        }

        ControlInjector.shared.sendScrollEvent(
            x: pt.x,
            y: pt.y,
            screenWidth: UInt16(videoDimensions.width),
            screenHeight: UInt16(videoDimensions.height),
            hScroll: hScroll,
            vScroll: vScroll
        )
    }

    // MARK: - Trackpad Gestures (Multi-touch Pinch-to-Zoom & Swipe Navigation)

    private var isPinching: Bool = false
    private var pinchCenter: (x: Int32, y: Int32) = (0, 0)
    private var pinchDistance: CGFloat = 120.0

    public override func magnify(with event: NSEvent) {
        guard videoDimensions.width > 0 && videoDimensions.height > 0 else { return }

        let location = convert(event.locationInWindow, from: nil)
        let centerPt = mapToAndroidPoint(location) ?? (x: Int32(videoDimensions.width / 2), y: Int32(videoDimensions.height / 2))

        let minDim = CGFloat(min(videoDimensions.width, videoDimensions.height))
        let maxDim = CGFloat(max(videoDimensions.width, videoDimensions.height))

        if event.phase.contains(.began) || (!isPinching && event.phase == []) {
            isPinching = true
            pinchCenter = centerPt
            pinchDistance = max(80.0, minDim * 0.2)

            let halfDist = Int32(pinchDistance / 2.0)
            let p0X = max(0, min(Int32(videoDimensions.width), centerPt.x - halfDist))
            let p1X = max(0, min(Int32(videoDimensions.width), centerPt.x + halfDist))

            // Pointer 0 DOWN
            ControlInjector.shared.sendTouchEvent(
                action: 0,
                pointerId: 0,
                x: p0X,
                y: centerPt.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 1.0,
                actionButton: 1,
                buttons: 1
            )

            // Pointer 1 DOWN (scrcpy controller automatically converts to ACTION_POINTER_DOWN)
            ControlInjector.shared.sendTouchEvent(
                action: 0,
                pointerId: 1,
                x: p1X,
                y: centerPt.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 1.0,
                actionButton: 1,
                buttons: 1
            )
        } else if event.phase.contains(.changed) || isPinching {
            let scaleFactor = 1.0 + event.magnification
            pinchDistance = max(40.0, min(maxDim * 0.85, pinchDistance * scaleFactor))

            let halfDist = Int32(pinchDistance / 2.0)
            let p0X = max(0, min(Int32(videoDimensions.width), pinchCenter.x - halfDist))
            let p1X = max(0, min(Int32(videoDimensions.width), pinchCenter.x + halfDist))

            // Pointer 0 MOVE
            ControlInjector.shared.sendTouchEvent(
                action: 2,
                pointerId: 0,
                x: p0X,
                y: pinchCenter.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 1.0,
                actionButton: 1,
                buttons: 1
            )

            // Pointer 1 MOVE
            ControlInjector.shared.sendTouchEvent(
                action: 2,
                pointerId: 1,
                x: p1X,
                y: pinchCenter.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 1.0,
                actionButton: 1,
                buttons: 1
            )
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard isPinching else { return }
            let halfDist = Int32(pinchDistance / 2.0)
            let p0X = max(0, min(Int32(videoDimensions.width), pinchCenter.x - halfDist))
            let p1X = max(0, min(Int32(videoDimensions.width), pinchCenter.x + halfDist))

            // Pointer 1 UP
            ControlInjector.shared.sendTouchEvent(
                action: 1,
                pointerId: 1,
                x: p1X,
                y: pinchCenter.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 0.0,
                actionButton: 1,
                buttons: 0
            )

            // Pointer 0 UP
            ControlInjector.shared.sendTouchEvent(
                action: 1,
                pointerId: 0,
                x: p0X,
                y: pinchCenter.y,
                screenWidth: UInt16(videoDimensions.width),
                screenHeight: UInt16(videoDimensions.height),
                pressure: 0.0,
                actionButton: 1,
                buttons: 0
            )

            isPinching = false
        }
    }

    public override func swipe(with event: NSEvent) {
        if event.deltaX > 0.4 {
            // Two-finger swipe right -> Android Back
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
        } else if event.deltaX < -0.4 {
            // Two-finger swipe left -> Android Back
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
        } else if event.deltaY < -0.4 {
            // Two-finger swipe down -> Pull notification drawer
            ControlInjector.shared.expandNotificationPanel()
        } else if event.deltaY > 0.4 {
            // Two-finger swipe up -> Home
            ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.home.rawValue)
        }
    }

    // MARK: - Keyboard & Clipboard

    public override func keyDown(with event: NSEvent) {
        // 1. Check for Command shortcuts (macOS muscle memory)
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "c" {
                // Command+C: Copy
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.copy.rawValue)
                return
            } else if key == "v" {
                // Command+V: Paste Mac clipboard directly into Android
                if let pbText = NSPasteboard.general.string(forType: .string) {
                    ControlInjector.shared.setClipboard(text: pbText, paste: true)
                }
                return
            } else if key == "a" {
                // Command+A: Select All (Ctrl+A in Android)
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.a.rawValue, metaState: 0x1000)
                return
            } else if key == "x" {
                // Command+X: Cut
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.cut.rawValue)
                return
            } else if key == "z" {
                // Command+Z: Undo / Redo
                if event.modifierFlags.contains(.shift) {
                    ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.z.rawValue, metaState: 0x1001)
                } else {
                    ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.z.rawValue, metaState: 0x1000)
                }
                return
            } else if key == "w" {
                // Command+W: Back
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
                return
            } else if key == "h" {
                // Command+H: Home
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.home.rawValue)
                return
            }

            // Command + Navigation
            if event.keyCode == 51 {
                // Command+Backspace: Delete line backwards
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.moveHome.rawValue, metaState: 0x0001)
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.del.rawValue)
                return
            } else if event.keyCode == 123 {
                // Command+Left: Start of line
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.moveHome.rawValue)
                return
            } else if event.keyCode == 124 {
                // Command+Right: End of line
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.moveEnd.rawValue)
                return
            } else if event.keyCode == 126 {
                // Command+Up: Top of page
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.moveHome.rawValue, metaState: 0x1000)
                return
            } else if event.keyCode == 125 {
                // Command+Down: Bottom of page
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.moveEnd.rawValue, metaState: 0x1000)
                return
            }
        }

        // 2. Check for Option shortcuts (macOS word navigation)
        if event.modifierFlags.contains(.option) {
            if event.keyCode == 51 {
                // Option+Backspace: Delete previous word (Ctrl+Backspace in Android)
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.del.rawValue, metaState: 0x1000)
                return
            } else if event.keyCode == 123 {
                // Option+Left: Previous word
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.dpadLeft.rawValue, metaState: 0x1000)
                return
            } else if event.keyCode == 124 {
                // Option+Right: Next word
                ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.dpadRight.rawValue, metaState: 0x1000)
                return
            }
        }

        // 3. Special navigation & control keys (Enter, Tab, Backspace, Esc, Arrows, PageUp/Down)
        if let specialKey = KeyMapper.mapSpecialKeyToAndroid(event.keyCode) {
            let repeatCount: Int32 = event.isARepeat ? 1 : 0
            ControlInjector.shared.sendKeycode(action: 0, keycode: specialKey.rawValue, repeatCount: repeatCount)
            return
        }

        // 4. Full-fidelity printable text injection (handles uppercase, numbers, symbols, international chars, emojis)
        if let chars = event.characters, !chars.isEmpty {
            // Discard unprintable ASCII control characters (< 0x20)
            let isPrintable = chars.unicodeScalars.allSatisfy { $0.value >= 0x20 || $0.value == 0x0A || $0.value == 0x09 }
            if isPrintable {
                ControlInjector.shared.sendText(chars)
                return
            }
        }

        // Fallback for any unhandled raw keys
        if let androidKey = KeyMapper.mapMacOSKeyCodeToAndroid(event.keyCode) {
            ControlInjector.shared.sendKeycode(action: 0, keycode: androidKey.rawValue)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if let specialKey = KeyMapper.mapSpecialKeyToAndroid(event.keyCode) {
            ControlInjector.shared.sendKeycode(action: 1, keycode: specialKey.rawValue)
        } else if let androidKey = KeyMapper.mapMacOSKeyCodeToAndroid(event.keyCode) {
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
