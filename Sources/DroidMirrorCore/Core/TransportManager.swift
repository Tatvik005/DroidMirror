import Foundation
import Combine
import SwiftUI

@MainActor
public final class TransportManager: ObservableObject {
    public static let shared = TransportManager()

    // MARK: - Published State

    @Published public var activeMode: ConnectionMode?
    @Published public var selectedMode: ConnectionMode = .usb
    @Published public var activeTargetSerial: String?

    @Published public var isConnecting: Bool = false
    @Published public var isPreflighting: Bool = false
    @Published public var alertBanner: String?
    @Published public var statusMessage: String = "Select a mode and click Connect"

    // Contextual Configuration Inputs
    @Published public var usbDeviceSerial: String = ""
    @Published public var detectedUSBDevices: [ADBDevice] = []

    @Published public var wifiInputIP: String = ""
    @Published public var phoneHotspotInputIP: String = ""

    // Multi-Device & Universal OEM Support
    @Published public var allDetectedDevices: [ADBDevice] = []
    @Published public var selectedDeviceSerial: String = ""
    @Published public var activeOEMDetails: OEMDetails?
    @Published public var currentEncoderTier: EncoderTier = .tier1_hardwareNative
    @Published public var isScreenLocked: Bool = false

    private var streamStartTime: Date?
    private var autoRetryCount: Int = 0
    private var devicePollingTask: Task<Void, Never>?

    // Live Metrics
    @Published public var fps: Int = 0
    @Published public var resolution: (width: Int, height: Int) = (0, 0)
    @Published public var isConnected: Bool = false
    @Published public var isScreenOff: Bool = false
    @Published public var isFloatingWindow: Bool = false
    @Published public var isHoveringFloatingWindow: Bool = false

    public weak var hostingWindow: NSWindow?

    public func attachWindow(_ window: NSWindow) {
        self.hostingWindow = window
    }

    public var isLandscape: Bool {
        return resolution.width > 0 && resolution.height > 0 && resolution.width > resolution.height
    }

    private var previousWindowFrame: NSRect?

    // Modals
    @Published public var showPairingModal: Bool = false
    @Published public var showHelpModal: Bool = false

    // Core Dependencies
    public let adb = ADBManager.shared
    public let decoder = H264Decoder()
    public lazy var streamClient = StreamClient(decoder: decoder, controlInjector: .shared)

    private var activeServerProcess: Process?

    public init() {
        setupDecoderCallbacks()
        startDevicePolling()
    }

    public func startDevicePolling() {
        devicePollingTask?.cancel()
        devicePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllDevices()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    public func refreshAllDevices() async {
        do {
            let devices = try await adb.getDevices()
            self.allDetectedDevices = devices
            let usbOnly = devices.filter { $0.isUSB }
            self.detectedUSBDevices = usbOnly

            if self.selectedDeviceSerial.isEmpty || !devices.contains(where: { $0.serial == self.selectedDeviceSerial }) {
                if let dev = devices.first(where: { $0.state == .device }) {
                    self.selectedDeviceSerial = dev.serial
                    if dev.isUSB && self.usbDeviceSerial.isEmpty {
                        self.usbDeviceSerial = dev.serial
                    }
                }
            }
        } catch {
            // Keep existing list on transient poll error
        }
    }

    public func selectDevice(bySerial serial: String) {
        guard let dev = allDetectedDevices.first(where: { $0.serial == serial }) else { return }
        self.selectedDeviceSerial = serial
        if dev.isUSB {
            self.usbDeviceSerial = dev.serial
            selectMode(.usb)
        } else if dev.isWiFi {
            let ipPart = String(dev.serial.split(separator: ":")[0])
            self.wifiInputIP = ipPart
            selectMode(.homeWiFi)
        }
        Task {
            let oem = await adb.fetchOEMDetails(serial: serial)
            self.activeOEMDetails = oem
        }
    }

    private func setupDecoderCallbacks() {
        decoder.onFPSUpdate = { [weak self] currentFPS in
            DispatchQueue.main.async {
                self?.fps = currentFPS
            }
        }

        decoder.onDimensionChange = { [weak self] width, height in
            DispatchQueue.main.async {
                self?.resolution = (width, height)
                self?.applyFloatingWindowBounds(animate: true)
            }
        }

        streamClient.onHandshakeCompleted = { [weak self] deviceName, res in
            DispatchQueue.main.async {
                self?.statusMessage = "Streaming from \(deviceName)"
                self?.isConnected = true
                self?.isConnecting = false
            }
        }

        streamClient.onResolutionChanged = { [weak self] width, height in
            DispatchQueue.main.async {
                self?.resolution = (width, height)
                self?.applyFloatingWindowBounds(animate: true)
            }
        }

        streamClient.onDisconnected = { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let elapsed = self.streamStartTime.map { Date().timeIntervalSince($0) } ?? 999.0

                // If stream died within 3.5 seconds of launching and we haven't exhausted tiers:
                if elapsed < 3.5 && self.autoRetryCount < 2 && self.currentEncoderTier != .tier3_universalSoftware {
                    self.autoRetryCount += 1
                    if self.currentEncoderTier == .tier1_hardwareNative {
                        self.currentEncoderTier = .tier2_hardwareAligned
                    } else {
                        self.currentEncoderTier = .tier3_universalSoftware
                    }
                    self.isConnected = false
                    self.isConnecting = true
                    self.statusMessage = "Phone codec rejected settings. Auto-recovering: \(self.currentEncoderTier.description)..."
                    self.alertBanner = "Auto-recovering: Switching to \(self.currentEncoderTier.description)"

                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        await self.applySelectedMode()
                    }
                    return
                }

                self.autoRetryCount = 0
                if let error = error {
                    self.alertBanner = "Stream disconnected: \(error.localizedDescription)"
                }
                self.isConnected = false
                self.isConnecting = false
                self.statusMessage = "Disconnected"
            }
        }
    }

    // MARK: - Explicit Mode Selection Button Actions

    public func selectMode(_ mode: ConnectionMode) {
        self.selectedMode = mode
        self.alertBanner = nil

        Task {
            await refreshContextForSelectedMode()
        }
    }

    public func refreshContextForSelectedMode() async {
        switch selectedMode {
        case .usb:
            await refreshUSBDevices()

        case .homeWiFi:
            var target = usbDeviceSerial
            if target.isEmpty {
                let devList = (try? await adb.getDevices()) ?? []
                if let dev = devList.first(where: { $0.state == .device }) {
                    target = dev.serial
                }
            }
            if !target.isEmpty {
                if target.contains(":") {
                    let ipPart = String(target.split(separator: ":")[0])
                    if isValidIPv4(ipPart) {
                        self.wifiInputIP = ipPart
                        self.statusMessage = "Target IP configured: \(ipPart)"
                    }
                } else if let wlanIP = await adb.queryPhoneWlanIP(serial: target) {
                    self.wifiInputIP = wlanIP
                    self.statusMessage = "Detected Phone Wi-Fi IP: \(wlanIP)"
                }
            }

        case .phoneHotspot:
            if let gw = await adb.getMacDefaultGatewayIP() {
                self.phoneHotspotInputIP = gw
                self.statusMessage = "Detected Phone Hotspot Gateway: \(gw)"
            } else if phoneHotspotInputIP.isEmpty {
                self.phoneHotspotInputIP = "192.168.43.1"
            }
        }
    }

    public func refreshUSBDevices() async {
        do {
            let devices = try await adb.getDevices()
            let usbOnly = devices.filter { $0.isUSB }
            self.detectedUSBDevices = usbOnly

            if let authorized = usbOnly.first(where: { $0.state == .device }) {
                self.usbDeviceSerial = authorized.serial
                self.statusMessage = "Found USB Device: \(authorized.displayName)"
            } else if let unauth = usbOnly.first(where: { $0.state == .unauthorized }) {
                self.usbDeviceSerial = unauth.serial
                self.alertBanner = "Phone '\(unauth.serial)' is unauthorized. Tap 'Allow USB Debugging' on the phone."
            } else if usbOnly.isEmpty {
                self.usbDeviceSerial = ""
                self.statusMessage = "No USB devices connected."
            }
        } catch {
            self.alertBanner = "Failed to query USB devices: \(error.localizedDescription)"
        }
    }

    // MARK: - Wireless Prep Helper (Port 5555 over USB)

    public func enableTCPIPOverUSB() async {
        guard !usbDeviceSerial.isEmpty else {
            self.alertBanner = "No USB device selected. Connect phone via USB first."
            return
        }

        self.statusMessage = "Enabling TCP/IP 5555 on \(usbDeviceSerial)..."
        let res = await adb.enableTCPIP(serial: usbDeviceSerial, port: 5555)
        switch res {
        case .success:
            self.statusMessage = "Port 5555 enabled on \(usbDeviceSerial)! Ready for wireless/hotspot."
            if let ip = await adb.queryPhoneWlanIP(serial: usbDeviceSerial) {
                self.wifiInputIP = ip
                self.statusMessage += " IP: \(ip)"
            }
        case .failure(let err):
            self.alertBanner = "Failed to enable TCP/IP 5555: \(err.localizedDescription)"
        }
    }

    // MARK: - Safe Manual Switch Execution (`applySelectedMode()`)

    public func applySelectedMode() async {
        self.alertBanner = nil
        self.isPreflighting = true
        self.statusMessage = "Running pre-flight validation for \(selectedMode.rawValue)..."

        var targetSerial: String = ""

        // STEP 1: PRE-FLIGHT CHECK
        switch selectedMode {
        case .usb:
            let usbCheck = await adb.checkUSBDeviceAvailable()
            switch usbCheck {
            case .success(let device):
                targetSerial = device.serial
                self.usbDeviceSerial = device.serial
            case .failure(let err):
                self.isPreflighting = false
                self.alertBanner = err.localizedDescription
                self.statusMessage = "Pre-flight failed: \(err.localizedDescription)"
                return
            }

        case .homeWiFi:
            let cleanIP = wifiInputIP.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanIP.isEmpty && isValidIPv4(cleanIP) else {
                self.isPreflighting = false
                self.alertBanner = "Invalid IP address: '\(wifiInputIP)'. Please enter a valid IPv4 address."
                return
            }

            self.statusMessage = "Testing reachability on \(cleanIP):5555..."
            let isReachable = adb.testTCPPort(ip: cleanIP, port: 5555, timeoutSeconds: 2.0)
            guard isReachable else {
                self.isPreflighting = false
                self.alertBanner = "Port 5555 unreachable on \(cleanIP). Did you click 'Prep for Wireless (Enable Port 5555)' over USB first?"
                self.statusMessage = "Connection aborted: Target port unreachable"
                return
            }

            self.statusMessage = "Connecting adb to \(cleanIP):5555..."
            let connectRes = await adb.connectTCP(ip: cleanIP, port: 5555)
            switch connectRes {
            case .success(let target):
                targetSerial = target
            case .failure(let err):
                self.isPreflighting = false
                self.alertBanner = "adb connect failed: \(err.localizedDescription)"
                return
            }

        case .phoneHotspot:
            let cleanIP = phoneHotspotInputIP.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanIP.isEmpty && isValidIPv4(cleanIP) else {
                self.isPreflighting = false
                self.alertBanner = "Invalid Phone Hotspot Gateway IP: '\(phoneHotspotInputIP)'."
                return
            }

            self.statusMessage = "Testing reachability on \(cleanIP):5555..."
            let isReachable = adb.testTCPPort(ip: cleanIP, port: 5555, timeoutSeconds: 2.0)
            guard isReachable else {
                self.isPreflighting = false
                self.alertBanner = "Port 5555 unreachable on \(cleanIP). Ensure Mac is connected to Phone's Wi-Fi Hotspot, and Port 5555 was enabled over USB first."
                self.statusMessage = "Connection aborted: Gateway port unreachable"
                return
            }

            self.statusMessage = "Connecting adb to \(cleanIP):5555..."
            let connectRes = await adb.connectTCP(ip: cleanIP, port: 5555)
            switch connectRes {
            case .success(let target):
                targetSerial = target
            case .failure(let err):
                self.isPreflighting = false
                self.alertBanner = "adb connect failed: \(err.localizedDescription)"
                return
            }
        }

        self.isPreflighting = false
        self.isConnecting = true
        self.statusMessage = "Pre-flight passed. Initializing stream on \(targetSerial)..."

        // STEP 2: SAFE ATOMIC SWITCH EXECUTION
        streamClient.disconnect()

        if let proc = activeServerProcess {
            proc.terminate()
            activeServerProcess = nil
        }

        // Clean up previous forward tunnel and any lingering scrcpy on device
        await adb.removePortForward(port: 27183)
        await adb.killExistingScrcpy(serial: targetSerial)

        // Universal OEM Diagnostics & Screen Wakefulness Shield
        await adb.wakeDeviceIfNeeded(serial: targetSerial)
        let oem = await adb.fetchOEMDetails(serial: targetSerial)
        self.activeOEMDetails = oem

        let locked = await adb.isScreenLocked(serial: targetSerial)
        self.isScreenLocked = locked
        if locked {
            if oem.isSamsung {
                self.alertBanner = "Samsung Knox Lockscreen: Screen is protected while locked. Type your PIN/password directly on Mac keyboard and press Enter to unlock."
            } else {
                self.statusMessage = "Phone is on lockscreen. Swipe or enter PIN to unlock."
            }
        } else if oem.isXiaomiGroup && alertBanner == nil {
            self.statusMessage = "Connected to \(oem.brandDisplayName). Ensure 'USB debugging (Security settings)' is ON in Developer Options for touch & keyboard control."
        }

        guard let localJar = await adb.resolveScrcpyServerPath() else {
            self.alertBanner = "scrcpy-server.jar not found. Please run setup.sh."
            self.isConnecting = false
            return
        }

        // Push server binary to device
        self.statusMessage = "Pushing scrcpy-server to \(targetSerial)..."
        let pushRes = await adb.pushServer(serial: targetSerial, localJarPath: localJar)
        guard case .success = pushRes else {
            self.alertBanner = "Failed to push scrcpy-server: \(pushRes)"
            self.isConnecting = false
            return
        }

        // Generate a unique session scid (31-bit positive) to prevent any abstract socket collisions
        let scid = Int32.random(in: 0x01000000...0x70000000)
        let scidHex = String(format: "%08x", scid)
        let abstractSocketName = "scrcpy_\(scidHex)"

        // Bind forward tunnel: adb -s <target> forward tcp:27183 localabstract:scrcpy_<scid>
        self.statusMessage = "Binding forward tunnel tcp:27183..."
        let fwdRes = await adb.setupPortForward(serial: targetSerial, localPort: 27183, remoteAbstract: abstractSocketName)
        guard case .success = fwdRes else {
            self.alertBanner = "Failed to forward tcp:27183 to localabstract:\(abstractSocketName)"
            self.isConnecting = false
            return
        }

        // Launch scrcpy-server with unique scid and active encoder tier
        self.statusMessage = "Launching scrcpy-server (\(currentEncoderTier.description))..."
        do {
            let proc = try await adb.launchScrcpyServer(serial: targetSerial, mode: selectedMode, scid: scid, tier: currentEncoderTier)
            self.activeServerProcess = proc
        } catch {
            self.alertBanner = "Failed to launch scrcpy-server: \(error.localizedDescription)"
            self.isConnecting = false
            return
        }

        // Connect StreamClient with scrcpy connect_to_server retry loop
        self.statusMessage = "Connecting video & control streams..."
        do {
            try streamClient.connect(port: 27183, maxAttempts: 50, delayMs: 100)
            self.activeMode = selectedMode
            self.activeTargetSerial = targetSerial
            self.isConnected = true
            self.streamStartTime = Date()
            if currentEncoderTier == .tier1_hardwareNative {
                self.statusMessage = "Connected to \(targetSerial) (\(selectedMode.shortTitle))"
            } else {
                self.statusMessage = "Connected to \(targetSerial) (\(currentEncoderTier.description))"
            }
            self.isConnecting = false

            // Auto-reset retry count after 5s of stable stream
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if self.isConnected {
                    self.autoRetryCount = 0
                }
            }
        } catch {
            self.alertBanner = "Failed to connect to scrcpy stream socket: \(error.localizedDescription)"
            self.isConnecting = false
            self.statusMessage = "Stream connection failed"
        }
    }

    public func disconnect() {
        if isFloatingWindow {
            toggleFloatingWindow()
        }
        streamClient.disconnect()
        if let proc = activeServerProcess {
            proc.terminate()
            activeServerProcess = nil
        }
        if let serial = activeTargetSerial {
            Task {
                await adb.killExistingScrcpy(serial: serial)
                await adb.removePortForward(port: 27183)
            }
        }
        activeMode = nil
        activeTargetSerial = nil
        isConnected = false
        isConnecting = false
        fps = 0
        currentEncoderTier = .tier1_hardwareNative
        autoRetryCount = 0
        statusMessage = "Disconnected"
    }

    // MARK: - Side Toolbar Actions

    public func togglePower() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.power.rawValue)
    }

    public func volumeUp() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.volumeUp.rawValue)
    }

    public func volumeDown() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.volumeDown.rawValue)
    }

    public func home() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.home.rawValue)
    }

    public func back() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.back.rawValue)
    }

    public func appSwitcher() {
        ControlInjector.shared.sendKeyClick(keycode: AndroidKeycode.appSwitch.rawValue)
    }

    public func toggleScreenOffMirroring() {
        isScreenOff.toggle()
        ControlInjector.shared.setDisplayPower(on: !isScreenOff)
        statusMessage = isScreenOff ? "Physical screen turned OFF (mirroring active)" : "Physical screen turned ON"
    }

    public func toggleDeviceRotation() {
        ControlInjector.shared.rotateDevice()
        if let serial = activeTargetSerial {
            Task {
                do {
                    let res = try await adb.runCommand(["-s", serial, "shell", "settings", "get", "system", "user_rotation"])
                    let next = (res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0") ? "1" : "0"
                    _ = try await adb.runCommand(["-s", serial, "shell", "settings", "put", "system", "accelerometer_rotation", "0"])
                    _ = try await adb.runCommand(["-s", serial, "shell", "settings", "put", "system", "user_rotation", next])
                } catch {
                    // In-flight scrcpy TYPE_ROTATE_DEVICE already dispatched
                }
            }
        }
    }

    // MARK: - Floating Compact Phone Window Mode (Strictly <= 6 Inches)

    public func toggleFloatingWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let window = self.hostingWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
                return
            }
            self.hostingWindow = window

            if self.isFloatingWindow {
                // Exit floating mode
                self.isFloatingWindow = false

                // Restore macOS window traffic lights
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false

                // Restore normal desktop window limits
                window.minSize = NSSize(width: 840, height: 680)
                window.contentMinSize = NSSize(width: 840, height: 680)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

                window.level = .normal
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
                window.isMovableByWindowBackground = false

                let targetFrame = self.previousWindowFrame ?? NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: 960,
                    height: 820
                )
                window.setFrame(targetFrame, display: true, animate: true)
            } else {
                // Enter floating mode
                self.previousWindowFrame = window.frame
                self.isFloatingWindow = true

                // Hide traffic lights for true smartphone look
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true

                self.applyFloatingWindowBounds(animate: true)
            }
        }
    }

    /// Automatically guarantees that the floating window is strictly sized like a real phone (<= 6 inches)
    /// in BOTH portrait and landscape orientations, adapting automatically to device rotation.
    public func applyFloatingWindowBounds(animate: Bool = true) {
        guard isFloatingWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let window = self.hostingWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
                return
            }
            self.hostingWindow = window

            let w = CGFloat(self.resolution.width)
            let h = CGFloat(self.resolution.height)
            let isLandscape = (w > 0 && h > 0) ? (w > h) : false

            // Strict 6-inch physical screen maximum:
            // Longest edge = 370pt (ensures diagonal on standard Mac displays is strictly <= 5.8 inches, never exceeding 6 inches)
            // Shortest edge = 370pt * aspect ratio
            let maxDimension: CGFloat = 370.0
            let aspect: CGFloat
            if w > 0 && h > 0 {
                aspect = min(w, h) / max(w, h)
            } else {
                aspect = 9.0 / 19.5
            }
            let shortDimension: CGFloat = max(150.0, min(190.0, round(maxDimension * aspect)))

            let targetWidth: CGFloat = isLandscape ? maxDimension : shortDimension
            let targetHeight: CGFloat = isLandscape ? shortDimension : maxDimension

            // CRITICAL: Unlock AppKit minSize and maxSize constraints so the window can shrink to real phone size
            window.minSize = NSSize(width: 100, height: 100)
            window.contentMinSize = NSSize(width: 100, height: 100)
            window.maxSize = NSSize(width: 500, height: 500)
            window.contentMaxSize = NSSize(width: 500, height: 500)

            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true

            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let newX = max(screenFrame.minX + 16, min(window.frame.origin.x, screenFrame.maxX - targetWidth - 20))
            let newY = max(screenFrame.minY + 16, min(window.frame.origin.y, screenFrame.maxY - targetHeight - 20))

            let targetFrame = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
            window.setFrame(targetFrame, display: true, animate: animate)
        }
    }

    public func handleDroppedFile(_ url: URL) {
        guard let serial = activeTargetSerial else {
            alertBanner = "Cannot transfer file: No device actively connected."
            return
        }

        Task {
            let isAPK = url.pathExtension.lowercased() == "apk"
            if isAPK {
                self.statusMessage = "Installing APK: \(url.lastPathComponent)..."
                let res = await adb.installAPK(serial: serial, apkPath: url.path)
                switch res {
                case .success:
                    self.statusMessage = "Successfully installed \(url.lastPathComponent)"
                case .failure(let err):
                    self.alertBanner = "APK installation failed: \(err.localizedDescription)"
                }
            } else {
                self.statusMessage = "Pushing file \(url.lastPathComponent)..."
                let res = await adb.pushFile(serial: serial, localPath: url.path)
                switch res {
                case .success:
                    self.statusMessage = "Pushed \(url.lastPathComponent) to /sdcard/Download/"
                case .failure(let err):
                    self.alertBanner = "File push failed: \(err.localizedDescription)"
                }
            }
        }
    }
}
