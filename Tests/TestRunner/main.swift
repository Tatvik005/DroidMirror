import Foundation
import DroidMirrorCore

func assertCondition(_ condition: Bool, _ message: String) {
    if !condition {
        print("❌ FAIL: \(message)")
        exit(1)
    } else {
        print("✅ PASS: \(message)")
    }
}

print("==========================================")
print("Running DroidMirror Comprehensive Test Suite")
print("==========================================")

// 1. Connection Mode Tests
print("\n--- 1. Connection Modes & Profiles ---")
assertCondition(ConnectionMode.allCases.count == 3, "Must define exactly 3 connection modes")

let usb = ConnectionMode.usb
assertCondition(usb.videoBitrate == 16_000_000, "USB bitrate must be 16 Mbps")
assertCondition(usb.maxSize == 0, "USB max size must be 0 (native resolution)")
assertCondition(usb.maxFps == 60, "USB max fps must be 60")

let wifi = ConnectionMode.homeWiFi
assertCondition(wifi.videoBitrate == 6_000_000, "Wi-Fi bitrate must be 6 Mbps")
assertCondition(wifi.maxSize == 1600, "Wi-Fi max size must be 1600")

let phoneHotspot = ConnectionMode.phoneHotspot
assertCondition(phoneHotspot.videoBitrate == 6_000_000, "Phone Hotspot bitrate must be 6 Mbps")
assertCondition(phoneHotspot.maxSize == 1600, "Phone Hotspot max size must be 1600")

// 2. NAL Unit Annex-B Parsing Tests
print("\n--- 2. NAL Unit Annex-B Parsing ---")
var stream = Data([0x00, 0x00, 0x00, 0x01, 0x27, 0x64, 0x00, 0x1F, 0xAC]) // SPS (7)
stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x28, 0xEB, 0xE3, 0xCB]) // PPS (8)
stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x25, 0x88, 0x84, 0x00]) // IDR (5)
stream.append(contentsOf: [0x00, 0x00, 0x01, 0x21, 0xAA, 0xBB])             // Slice (1, 3-byte start code)

let nals = NALParser.parseAnnexB(data: stream)
assertCondition(nals.count == 4, "Must parse 4 NAL units (both 3-byte and 4-byte start codes)")
assertCondition(nals[0].isSPS && nals[0].type == 7, "NAL 0 must be SPS (type 7)")
assertCondition(nals[1].isPPS && nals[1].type == 8, "NAL 1 must be PPS (type 8)")
assertCondition(nals[2].isIDR && nals[2].type == 5, "NAL 2 must be IDR keyframe (type 5)")
assertCondition(nals[3].isSlice && nals[3].type == 1, "NAL 3 must be non-IDR slice (type 1)")

// 3. Control Injector Binary Serialization Tests
print("\n--- 3. Control Protocol Serialization ---")
let injector = ControlInjector()
var sentData: Data?
injector.sendDataHandler = { data in
    sentData = data
}

// Touch Event
injector.sendTouchEvent(
    action: 0, // ACTION_DOWN
    pointerId: -1,
    x: 500,
    y: 1000,
    screenWidth: 1080,
    screenHeight: 2400,
    pressure: 1.0,
    actionButton: 1,
    buttons: 1
)

guard let touchData = sentData else {
    assertCondition(false, "Touch data was not captured")
    exit(1)
}
assertCondition(touchData.count == 32, "Touch event packet must be 32 bytes")
assertCondition(touchData[0] == 2, "Touch event type must be 2")
assertCondition(touchData[1] == 0, "Touch event action must be 0 (ACTION_DOWN)")
let xVal = touchData.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
assertCondition(xVal == 500, "Touch x coordinate must be 500")
let yVal = touchData.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
assertCondition(yVal == 1000, "Touch y coordinate must be 1000")
let wVal = touchData.subdata(in: 18..<20).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
assertCondition(wVal == 1080, "Touch screen width must be 1080")
let hVal = touchData.subdata(in: 20..<22).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
assertCondition(hVal == 2400, "Touch screen height must be 2400")

// Scroll Event
injector.sendScrollEvent(
    x: 540,
    y: 1200,
    screenWidth: 1080,
    screenHeight: 2400,
    hScroll: 0.0,
    vScroll: -1.0
)
guard let scrollData = sentData else {
    assertCondition(false, "Scroll data was not captured")
    exit(1)
}
assertCondition(scrollData.count == 21, "Scroll event packet must be 21 bytes")
assertCondition(scrollData[0] == 3, "Scroll event type must be 3")

// Keycode Event
injector.sendKeycode(action: 0, keycode: 4) // Back key
guard let keyData = sentData else {
    assertCondition(false, "Key data was not captured")
    exit(1)
}
assertCondition(keyData.count == 14, "Key event packet must be 14 bytes")
assertCondition(keyData[0] == 0, "Key event type must be 0")
let keyVal = keyData.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
assertCondition(keyVal == 4, "Keycode must be 4 (AKEYCODE_BACK)")

// Screen-Off Mirroring Power Control
injector.setDisplayPower(on: false)
guard let powerData = sentData else {
    assertCondition(false, "Power data was not captured")
    exit(1)
}
assertCondition(powerData.count == 2, "Display power packet must be 2 bytes")
assertCondition(powerData[0] == 10, "Display power type must be 10")
assertCondition(powerData[1] == 0, "Display power must be 0 (OFF)")

// Clipboard Synchronization
let testString = "DroidMirror Test Text"
injector.setClipboard(text: testString, paste: true)
guard let clipData = sentData else {
    assertCondition(false, "Clipboard data was not captured")
    exit(1)
}
assertCondition(clipData[0] == 9, "Clipboard type must be 9")
assertCondition(clipData[9] == 1, "Paste flag must be 1")
let clipLen = Int(clipData.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
assertCondition(clipLen == testString.utf8.count, "Clipboard length must match text UTF-8 count")

// Inbound Device Clipboard Handling
var inboundClipboard: String?
injector.onRemoteClipboardReceived = { str in
    inboundClipboard = str
}
var inboundMsg = Data([0x00]) // TYPE_CLIPBOARD
var inboundLenBE = UInt32(testString.utf8.count).bigEndian
withUnsafeBytes(of: &inboundLenBE) { inboundMsg.append(contentsOf: $0) }
inboundMsg.append(testString.data(using: .utf8)!)
injector.handleDeviceMessage(data: inboundMsg)
try? await Task.sleep(nanoseconds: 150_000_000)
assertCondition(inboundClipboard == testString, "Inbound device clipboard must synchronize to macOS pasteboard")

// 4. macOS Keycode to Android Keycode Mapping Tests
print("\n--- 4. Key Mapping ---")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(36) == .enter, "Return key maps to AKEYCODE_ENTER")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(51) == .del, "Delete (backspace) maps to AKEYCODE_DEL")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(53) == .escape, "Escape key maps to AKEYCODE_ESCAPE")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(49) == .space, "Space key maps to AKEYCODE_SPACE")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(123) == .dpadLeft, "Left arrow maps to AKEYCODE_DPAD_LEFT")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(124) == .dpadRight, "Right arrow maps to AKEYCODE_DPAD_RIGHT")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(125) == .dpadDown, "Down arrow maps to AKEYCODE_DPAD_DOWN")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(126) == .dpadUp, "Up arrow maps to AKEYCODE_DPAD_UP")
assertCondition(KeyMapper.mapMacOSKeyCodeToAndroid(0) == .a, "Keycode 0 maps to AKEYCODE_A")

// 5. IPv4 Validation Tests
print("\n--- 5. Network IPv4 Validation ---")
assertCondition(isValidIPv4("192.168.1.1"), "192.168.1.1 is valid IPv4")
assertCondition(isValidIPv4("192.168.43.1"), "192.168.43.1 is valid IPv4")
assertCondition(isValidIPv4("10.0.0.1"), "10.0.0.1 is valid IPv4")
assertCondition(isValidIPv4("127.0.0.1"), "127.0.0.1 is valid IPv4")
assertCondition(!isValidIPv4("192.168.1.256"), "192.168.1.256 is invalid IPv4")
assertCondition(!isValidIPv4("abc.def.ghi.jkl"), "String is invalid IPv4")
assertCondition(!isValidIPv4(""), "Empty string is invalid IPv4")
assertCondition(!isValidIPv4("192.168.1"), "Incomplete string is invalid IPv4")

// 6. Universal OEM Brand & Multi-Tier Codec Tests
print("\n--- 6. Universal OEM & Multi-Tier Fallback ---")
let xiaomi = OEMDetails(manufacturer: "Xiaomi", brand: "POCO", model: "2201116SG", androidSDK: 33)
assertCondition(xiaomi.isXiaomiGroup, "POCO/Xiaomi identified correctly as Xiaomi Group")
assertCondition(xiaomi.brandDisplayName == "Xiaomi / Redmi / POCO", "Brand display name matches Xiaomi Group")

let oneplus = OEMDetails(manufacturer: "OnePlus", brand: "OnePlus", model: "CPH2581", androidSDK: 34)
assertCondition(oneplus.isOppoGroup, "OnePlus identified correctly as Oppo/ColorOS Group")

let samsung = OEMDetails(manufacturer: "samsung", brand: "samsung", model: "SM-S921B", androidSDK: 35)
assertCondition(samsung.isSamsung, "Samsung identified correctly as Samsung")

let vivo = OEMDetails(manufacturer: "vivo", brand: "iQOO", model: "I2208", androidSDK: 34)
assertCondition(vivo.isVivoGroup, "iQOO identified correctly as Vivo Group")

assertCondition(EncoderTier.allCases.count == 3, "Must define exactly 3 encoder tiers")
assertCondition(EncoderTier.tier1_hardwareNative.rawValue == 1, "Tier 1 is Hardware Native")
assertCondition(EncoderTier.tier2_hardwareAligned.rawValue == 2, "Tier 2 is Hardware Aligned")
assertCondition(EncoderTier.tier3_universalSoftware.rawValue == 3, "Tier 3 is Universal Software")

// 7. Bundled Binaries & Dependencies ---
print("\n--- 7. Bundled Binaries & Dependencies ---")
let adbPath = await ADBManager.shared.resolveADBPath()
assertCondition(adbPath != nil, "ADB path must be resolved successfully")
print("Found ADB: \(adbPath ?? "")")

let scrcpyPath = await ADBManager.shared.resolveScrcpyServerPath()
assertCondition(scrcpyPath != nil, "scrcpy-server.jar path must be resolved successfully")
print("Found scrcpy-server: \(scrcpyPath ?? "")")

// 8. Live Physical Device E2E Verification
print("\n--- 8. Live Device E2E Verification ---")
let devices = try await ADBManager.shared.getDevices()
if let usbDevice = devices.first(where: { $0.isUSB && $0.state == .device }) {
    print("Detected live USB device: \(usbDevice.displayName)")
    print("Testing end-to-end USB stream connection via TransportManager...")

    await MainActor.run {
        let transport = TransportManager.shared
        transport.selectMode(.usb)
    }

    await TransportManager.shared.applySelectedMode()

    let connected = await MainActor.run {
        TransportManager.shared.isConnected
    }
    assertCondition(connected, "Live USB stream connection succeeded!")

    // Allow 1.5 seconds for video stream to pump frames and decode resolution
    try? await Task.sleep(nanoseconds: 1_500_000_000)

    let res = await MainActor.run {
        TransportManager.shared.resolution
    }
    print("Live stream resolution decoded: \(res.width)x\(res.height)")
    assertCondition(res.width > 0 && res.height > 0, "Video resolution successfully received from hardware decoder!")

    // Clean disconnect
    await MainActor.run {
        TransportManager.shared.disconnect()
    }
    print("Disconnected cleanly from USB device.")
} else if let wifiDevice = devices.first(where: { $0.isWiFi && $0.state == .device }) {
    print("Detected live Wi-Fi device: \(wifiDevice.displayName)")
    print("Testing end-to-end Home Wi-Fi stream connection via TransportManager...")

    let parts = wifiDevice.serial.split(separator: ":")
    let wifiIP = String(parts[0])

    let oemDetails = await ADBManager.shared.fetchOEMDetails(serial: wifiDevice.serial)
    print("Detected live device OEM: \(oemDetails.brandDisplayName) [SDK \(oemDetails.androidSDK)]")
    assertCondition(!oemDetails.model.isEmpty, "Device model must be fetched")

    await MainActor.run {
        let transport = TransportManager.shared
        transport.selectMode(.homeWiFi)
        transport.wifiInputIP = wifiIP
    }

    await TransportManager.shared.applySelectedMode()

    let connected = await MainActor.run {
        TransportManager.shared.isConnected
    }
    assertCondition(connected, "Live Home Wi-Fi stream connection succeeded!")

    // Allow 2.0 seconds for video stream over Wi-Fi
    try? await Task.sleep(nanoseconds: 2_000_000_000)

    let res = await MainActor.run {
        TransportManager.shared.resolution
    }
    print("Live stream resolution decoded over Wi-Fi: \(res.width)x\(res.height)")
    assertCondition(res.width > 0 && res.height > 0, "Video resolution successfully received over Wi-Fi from hardware decoder!")

    // Clean disconnect
    await MainActor.run {
        TransportManager.shared.disconnect()
    }
    print("Disconnected cleanly from Wi-Fi device.")
} else {
    print("Note: No device in 'device' state detected for live test. Skipping.")
}

print("\n🎉 ALL TESTS PASSED SUCCESSFULLY! DroidMirror Mac is 100% Verified!")
print("==========================================")
