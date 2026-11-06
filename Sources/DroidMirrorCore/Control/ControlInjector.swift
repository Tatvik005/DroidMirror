import Foundation
import AppKit

public final class ControlInjector {
    public static let shared = ControlInjector()

    public var sendDataHandler: ((Data) -> Void)?
    public var onRemoteClipboardReceived: ((String) -> Void)?

    public init() {}

    // MARK: - Touch Events

    /// Injects touch event (ACTION_DOWN = 0, ACTION_UP = 1, ACTION_MOVE = 2)
    public func sendTouchEvent(
        action: UInt8,
        pointerId: Int64 = -1,
        x: Int32,
        y: Int32,
        screenWidth: UInt16,
        screenHeight: UInt16,
        pressure: Float = 1.0,
        actionButton: Int32 = 1, // BUTTON_PRIMARY
        buttons: Int32 = 1
    ) {
        var data = Data()
        data.append(2) // TYPE_INJECT_TOUCH_EVENT
        data.append(action)

        var pointerBE = pointerId.bigEndian
        withUnsafeBytes(of: &pointerBE) { data.append(contentsOf: $0) }

        var xBE = x.bigEndian
        withUnsafeBytes(of: &xBE) { data.append(contentsOf: $0) }

        var yBE = y.bigEndian
        withUnsafeBytes(of: &yBE) { data.append(contentsOf: $0) }

        var widthBE = screenWidth.bigEndian
        withUnsafeBytes(of: &widthBE) { data.append(contentsOf: $0) }

        var heightBE = screenHeight.bigEndian
        withUnsafeBytes(of: &heightBE) { data.append(contentsOf: $0) }

        // Pressure is encoded as 16-bit fixed point: [0, 1] -> [0, 0xFFFF]
        let clampedPressure = max(0.0, min(1.0, pressure))
        var pressureU16 = UInt16(clampedPressure * 65535.0).bigEndian
        withUnsafeBytes(of: &pressureU16) { data.append(contentsOf: $0) }

        var actionButtonBE = actionButton.bigEndian
        withUnsafeBytes(of: &actionButtonBE) { data.append(contentsOf: $0) }

        var buttonsBE = buttons.bigEndian
        withUnsafeBytes(of: &buttonsBE) { data.append(contentsOf: $0) }

        sendDataHandler?(data)
    }

    // MARK: - Scroll Events

    public func sendScrollEvent(
        x: Int32,
        y: Int32,
        screenWidth: UInt16,
        screenHeight: UInt16,
        hScroll: Float,
        vScroll: Float,
        buttons: Int32 = 0
    ) {
        var data = Data()
        data.append(3) // TYPE_INJECT_SCROLL_EVENT

        var xBE = x.bigEndian
        withUnsafeBytes(of: &xBE) { data.append(contentsOf: $0) }

        var yBE = y.bigEndian
        withUnsafeBytes(of: &yBE) { data.append(contentsOf: $0) }

        var widthBE = screenWidth.bigEndian
        withUnsafeBytes(of: &widthBE) { data.append(contentsOf: $0) }

        var heightBE = screenHeight.bigEndian
        withUnsafeBytes(of: &heightBE) { data.append(contentsOf: $0) }

        // hScroll and vScroll in range [-16, 16] mapped to 16-bit fixed point [-0x7FFF, 0x7FFF]
        let hClamped = max(-16.0, min(16.0, hScroll)) / 16.0
        let vClamped = max(-16.0, min(16.0, vScroll)) / 16.0
        var hInt16 = Int16(hClamped * 32767.0).bigEndian
        var vInt16 = Int16(vClamped * 32767.0).bigEndian
        withUnsafeBytes(of: &hInt16) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &vInt16) { data.append(contentsOf: $0) }

        var buttonsBE = buttons.bigEndian
        withUnsafeBytes(of: &buttonsBE) { data.append(contentsOf: $0) }

        sendDataHandler?(data)
    }

    // MARK: - Key Events

    public func sendKeycode(action: UInt8, keycode: Int32, repeatCount: Int32 = 0, metaState: Int32 = 0) {
        var data = Data()
        data.append(0) // TYPE_INJECT_KEYCODE
        data.append(action) // 0: ACTION_DOWN, 1: ACTION_UP

        var keyBE = keycode.bigEndian
        withUnsafeBytes(of: &keyBE) { data.append(contentsOf: $0) }

        var repeatBE = repeatCount.bigEndian
        withUnsafeBytes(of: &repeatBE) { data.append(contentsOf: $0) }

        var metaBE = metaState.bigEndian
        withUnsafeBytes(of: &metaBE) { data.append(contentsOf: $0) }

        sendDataHandler?(data)
    }

    public func sendKeyClick(keycode: Int32, metaState: Int32 = 0) {
        sendKeycode(action: 0, keycode: keycode, repeatCount: 0, metaState: metaState)
        sendKeycode(action: 1, keycode: keycode, repeatCount: 0, metaState: metaState)
    }

    public func sendBackOrScreenOn(action: UInt8) {
        var data = Data()
        data.append(4) // TYPE_BACK_OR_SCREEN_ON
        data.append(action)
        sendDataHandler?(data)
    }

    public func sendText(_ text: String) {
        guard let utf8 = text.data(using: .utf8), !utf8.isEmpty else { return }
        var data = Data()
        data.append(1) // TYPE_INJECT_TEXT

        var lengthBE = UInt32(utf8.count).bigEndian
        withUnsafeBytes(of: &lengthBE) { data.append(contentsOf: $0) }
        data.append(utf8)

        sendDataHandler?(data)
    }

    // MARK: - Screen-Off Mirroring & Display Control

    public func setDisplayPower(on: Bool) {
        var data = Data()
        data.append(10) // TYPE_SET_DISPLAY_POWER
        data.append(on ? 1 : 0)
        sendDataHandler?(data)
    }

    // MARK: - Clipboard Synchronization

    public func setClipboard(text: String, paste: Bool = false) {
        let utf8 = text.data(using: .utf8) ?? Data()
        var data = Data()
        data.append(9) // TYPE_SET_CLIPBOARD

        var seqBE: Int64 = 0 // SEQUENCE_INVALID
        withUnsafeBytes(of: &seqBE) { data.append(contentsOf: $0) }

        data.append(paste ? 1 : 0)

        var lengthBE = UInt32(utf8.count).bigEndian
        withUnsafeBytes(of: &lengthBE) { data.append(contentsOf: $0) }
        data.append(utf8)

        sendDataHandler?(data)
    }

    public func getClipboard(copyKey: UInt8 = 1) {
        var data = Data()
        data.append(8) // TYPE_GET_CLIPBOARD
        data.append(copyKey)
        sendDataHandler?(data)
    }

    // MARK: - Navigation Shortcuts

    public func expandNotificationPanel() {
        sendDataHandler?(Data([5]))
    }

    public func expandSettingsPanel() {
        sendDataHandler?(Data([6]))
    }

    public func collapsePanels() {
        sendDataHandler?(Data([7]))
    }

    public func rotateDevice() {
        sendDataHandler?(Data([11]))
    }

    // MARK: - Handle Inbound Device Messages

    public func handleDeviceMessage(data: Data) {
        guard !data.isEmpty else { return }
        let msgType = data[0]
        if msgType == 0 { // TYPE_CLIPBOARD
            guard data.count >= 5 else { return }
            let len = Int(UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4]))
            if data.count >= 5 + len {
                let textData = data.subdata(in: 5..<(5 + len))
                if let str = String(data: textData, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(str, forType: .string)
                        self?.onRemoteClipboardReceived?(str)
                    }
                }
            }
        }
    }
}
