import Foundation
import Darwin

public enum ADBDeviceState: String, Sendable {
    case device
    case unauthorized
    case offline
    case authorizing
    case unknown
}

public struct ADBDevice: Identifiable, Hashable, Sendable {
    public let serial: String
    public let state: ADBDeviceState
    public let product: String?
    public let model: String?
    public let device: String?
    public let transportId: String?
    public let isUSB: Bool
    public let isWiFi: Bool

    public init(
        serial: String,
        state: ADBDeviceState,
        product: String? = nil,
        model: String? = nil,
        device: String? = nil,
        transportId: String? = nil,
        isUSB: Bool,
        isWiFi: Bool
    ) {
        self.serial = serial
        self.state = state
        self.product = product
        self.model = model
        self.device = device
        self.transportId = transportId
        self.isUSB = isUSB
        self.isWiFi = isWiFi
    }

    public var id: String { serial }

    public var displayName: String {
        let typeTag = isUSB ? "USB" : "Wi-Fi"
        if let model = model {
            let cleanModel = model.replacingOccurrences(of: "_", with: " ")
            return "\(cleanModel) [\(typeTag)] (\(serial))"
        }
        return "\(serial) [\(typeTag)]"
    }
}

public struct OEMDetails: Equatable, Sendable {
    public let manufacturer: String
    public let brand: String
    public let model: String
    public let androidSDK: Int

    public init(manufacturer: String, brand: String, model: String, androidSDK: Int) {
        self.manufacturer = manufacturer
        self.brand = brand
        self.model = model
        self.androidSDK = androidSDK
    }

    public var isXiaomiGroup: Bool {
        let m = manufacturer.lowercased()
        let b = brand.lowercased()
        return m.contains("xiaomi") || b.contains("xiaomi") || b.contains("redmi") || b.contains("poco")
    }

    public var isOppoGroup: Bool {
        let m = manufacturer.lowercased()
        let b = brand.lowercased()
        return m.contains("oppo") || b.contains("oppo") || b.contains("oneplus") || b.contains("realme")
    }

    public var isVivoGroup: Bool {
        let m = manufacturer.lowercased()
        let b = brand.lowercased()
        return m.contains("vivo") || b.contains("vivo") || b.contains("iqoo")
    }

    public var isSamsung: Bool {
        let m = manufacturer.lowercased()
        let b = brand.lowercased()
        return m.contains("samsung") || b.contains("samsung")
    }

    public var isHuaweiGroup: Bool {
        let m = manufacturer.lowercased()
        let b = brand.lowercased()
        return m.contains("huawei") || b.contains("huawei") || b.contains("honor")
    }

    public var brandDisplayName: String {
        if isXiaomiGroup { return "Xiaomi / Redmi / POCO" }
        if isOppoGroup { return "OPPO / OnePlus / Realme" }
        if isVivoGroup { return "Vivo / iQOO" }
        if isSamsung { return "Samsung Galaxy" }
        if isHuaweiGroup { return "Huawei / Honor" }
        let m = manufacturer.lowercased()
        if m.contains("google") { return "Google Pixel" }
        if m.contains("motorola") { return "Motorola" }
        if m.contains("nothing") { return "Nothing Phone" }
        return manufacturer.capitalized
    }
}

public enum EncoderTier: Int, CaseIterable, Sendable {
    case tier1_hardwareNative = 1      // Native HW encoder at default profile
    case tier2_hardwareAligned = 2     // Safe 720p/1080p alignment (1280px max, 30 fps, 4 Mbps)
    case tier3_universalSoftware = 3   // Guaranteed AOSP software encoder (c2.android.avc.encoder, 1024px max, 30 fps, 2 Mbps)

    public var description: String {
        switch self {
        case .tier1_hardwareNative:
            return "Hardware Accelerated (Native)"
        case .tier2_hardwareAligned:
            return "Hardware Compatibility (Aligned 720p/30fps)"
        case .tier3_universalSoftware:
            return "Universal AOSP Software Encoder"
        }
    }
}

public enum ADBError: LocalizedError {
    case adbNotFound
    case scrcpyServerNotFound
    case executionFailed(String)
    case deviceNotFound(String)
    case unauthorized(String)
    case offline(String)
    case portUnreachable(ip: String, port: Int, reason: String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb executable not found. Please install Android Platform Tools or run setup.sh."
        case .scrcpyServerNotFound:
            return "scrcpy-server.jar not found in Resources/."
        case .executionFailed(let msg):
            return "ADB command failed: \(msg)"
        case .deviceNotFound(let msg):
            return "Device not found: \(msg)"
        case .unauthorized(let msg):
            return "Device unauthorized: \(msg)"
        case .offline(let msg):
            return "Device offline: \(msg)"
        case .portUnreachable(let ip, let port, let reason):
            return "Port \(port) unreachable on \(ip). \(reason)"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        }
    }
}

public actor ADBManager {
    public static let shared = ADBManager()

    private var cachedADBPath: String?
    private var cachedScrcpyPath: String?

    public init() {}

    // MARK: - Binary Resolution

    public func resolveADBPath() -> String? {
        if let cached = cachedADBPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/adb" },
            FileManager.default.currentDirectoryPath + "/Resources/adb",
            FileManager.default.currentDirectoryPath + "/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            "/usr/bin/adb"
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedADBPath = path
                return path
            }
        }

        // Check PATH
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["adb"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                cachedADBPath = output
                return output
            }
        }

        return nil
    }

    public func resolveScrcpyServerPath() -> String? {
        if let cached = cachedScrcpyPath, FileManager.default.fileExists(atPath: cached) {
            return cached
        }

        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/scrcpy-server.jar" },
            FileManager.default.currentDirectoryPath + "/Resources/scrcpy-server.jar",
            FileManager.default.currentDirectoryPath + "/scrcpy-server.jar"
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                cachedScrcpyPath = path
                return path
            }
        }
        return nil
    }

    // MARK: - Process Execution

    @discardableResult
    public func runCommand(_ args: [String], timeout: TimeInterval = 10.0) async throws -> (status: Int32, stdout: String, stderr: String) {
        guard let adb = resolveADBPath() else {
            throw ADBError.adbNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: adb)
                process.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var didResume = false
                let resumeLock = NSLock()

                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    if !didResume {
                        didResume = true
                        process.terminate()
                        continuation.resume(throwing: ADBError.executionFailed("Command timed out after \(timeout)s: adb \(args.joined(separator: " "))"))
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()

                    timer.cancel()
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    if !didResume {
                        didResume = true
                        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let stdoutStr = String(data: outData, encoding: .utf8) ?? ""
                        let stderrStr = String(data: errData, encoding: .utf8) ?? ""
                        continuation.resume(returning: (process.terminationStatus, stdoutStr, stderrStr))
                    }
                } catch {
                    timer.cancel()
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Device Discovery & Pre-Flights

    public func getDevices() async throws -> [ADBDevice] {
        let result = try await runCommand(["devices", "-l"])
        guard result.status == 0 else {
            throw ADBError.executionFailed(result.stderr)
        }

        var devices: [ADBDevice] = []
        let lines = result.stdout.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "List of devices attached") {
                continue
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let rawState = parts[1]
            let state: ADBDeviceState
            switch rawState {
            case "device": state = .device
            case "unauthorized": state = .unauthorized
            case "offline": state = .offline
            case "authorizing": state = .authorizing
            default: state = .unknown
            }

            var product: String?
            var model: String?
            var device: String?
            var transportId: String?

            for part in parts.dropFirst(2) {
                if part.starts(with: "product:") {
                    product = String(part.dropFirst("product:".count))
                } else if part.starts(with: "model:") {
                    model = String(part.dropFirst("model:".count))
                } else if part.starts(with: "device:") {
                    device = String(part.dropFirst("device:".count))
                } else if part.starts(with: "transport_id:") {
                    transportId = String(part.dropFirst("transport_id:".count))
                }
            }

            let isWiFi = serial.contains(":") || serial.range(of: #"^\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil
            let isUSB = !isWiFi

            devices.append(ADBDevice(
                serial: serial,
                state: state,
                product: product,
                model: model,
                device: device,
                transportId: transportId,
                isUSB: isUSB,
                isWiFi: isWiFi
            ))
        }

        return devices
    }

    public func checkUSBDeviceAvailable() async -> Result<ADBDevice, ADBError> {
        do {
            let devices = try await getDevices()
            let usbDevices = devices.filter { $0.isUSB }

            if usbDevices.isEmpty {
                return .failure(.deviceNotFound("No physical USB Android device detected. Connect a USB cable and ensure USB Debugging is turned ON in Developer Options."))
            }

            if let authorized = usbDevices.first(where: { $0.state == .device }) {
                return .success(authorized)
            }

            if let unauthorized = usbDevices.first(where: { $0.state == .unauthorized }) {
                return .failure(.unauthorized("Phone '\(unauthorized.serial)' is unauthorized. Unlock the device and tap 'Allow USB Debugging' on the popup prompt."))
            }

            if let offline = usbDevices.first(where: { $0.state == .offline }) {
                return .failure(.offline("Phone '\(offline.serial)' is offline. Unplug and re-plug the USB cable."))
            }

            return .failure(.deviceNotFound("USB device detected but not in usable state (\(usbDevices.first?.state.rawValue ?? "unknown"))."))
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    public func killExistingScrcpy(serial: String) async {
        _ = try? await runCommand(["-s", serial, "shell", "pkill -f com.genymobile.scrcpy || true"])
    }

    public func enableTCPIP(serial: String, port: Int = 5555) async -> Result<Void, ADBError> {
        do {
            let result = try await runCommand(["-s", serial, "tcpip", String(port)])
            if result.status == 0 || result.stdout.contains("restarting in TCP mode") {
                return .success(())
            } else {
                return .failure(.executionFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    public func queryPhoneWlanIP(serial: String) async -> String? {
        if let res = try? await runCommand(["-s", serial, "shell", "ip route"]), res.status == 0 {
            for line in res.stdout.components(separatedBy: .newlines) {
                if line.contains("wlan0") && line.contains("src ") {
                    let tokens = line.split(separator: " ").map(String.init)
                    if let srcIdx = tokens.firstIndex(of: "src"), srcIdx + 1 < tokens.count {
                        let ip = tokens[srcIdx + 1]
                        if isValidIPv4(ip) { return ip }
                    }
                }
            }
        }

        if let res = try? await runCommand(["-s", serial, "shell", "ip -f inet addr show wlan0"]), res.status == 0 {
            let pattern = #"inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: res.stdout, range: NSRange(res.stdout.startIndex..., in: res.stdout)),
               let range = Range(match.range(at: 1), in: res.stdout) {
                let ip = String(res.stdout[range])
                if isValidIPv4(ip) { return ip }
            }
        }

        if let res = try? await runCommand(["-s", serial, "shell", "getprop dhcp.wlan0.ipaddress"]), res.status == 0 {
            let ip = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidIPv4(ip) { return ip }
        }

        return nil
    }

    // MARK: - Hotspot & Network Discovery

    public func getMacDefaultGatewayIP() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.starts(with: "gateway:") {
                        let parts = trimmed.split(separator: ":").map(String.init)
                        if parts.count >= 2 {
                            let ip = parts[1].trimmingCharacters(in: .whitespaces)
                            if isValidIPv4(ip) { return ip }
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    public func scanMacHotspotClients() -> [String] {
        var discoveredIPs: [String] = []

        // 1. Query /var/db/dhcpd_leases for active leases assigned by macOS Internet Sharing (bootpd)
        let leasePaths = ["/var/db/dhcpd_leases", "/private/var/db/dhcpd_leases"]
        for p in leasePaths {
            if let leaseData = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let leaseStr = String(data: leaseData, encoding: .utf8) {
                for line in leaseStr.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.starts(with: "ip_address=") {
                        let ip = String(trimmed.dropFirst("ip_address=".count)).trimmingCharacters(in: .whitespaces)
                        if isValidIPv4(ip) && !discoveredIPs.contains(ip) && !ip.hasSuffix(".1") && !ip.hasSuffix(".255") {
                            discoveredIPs.append(ip)
                        }
                    }
                }
            }
        }

        // 2. Query ARP table on bridge interfaces, ignoring incomplete, broadcast, and permanent (self)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-a"]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    if trimmed.contains("(incomplete)") || trimmed.contains("permanent") || trimmed.contains(".255") || trimmed.contains("224.0.") {
                        continue
                    }
                    if trimmed.contains("bridge") || trimmed.contains("192.168.2.") {
                        if let start = trimmed.firstIndex(of: "("),
                           let end = trimmed.firstIndex(of: ")"),
                           start < end {
                            let ip = String(trimmed[trimmed.index(after: start)..<end])
                            if isValidIPv4(ip) && !discoveredIPs.contains(ip) && !ip.hasSuffix(".1") && !ip.hasSuffix(".255") {
                                discoveredIPs.append(ip)
                            }
                        }
                    }
                }
            }
        } catch {}

        return discoveredIPs
    }

    private nonisolated func singleProbeTCPPort(ip: String, port: Int, timeoutSeconds: Double) -> Bool {
        guard isValidIPv4(ip) else { return false }

        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, ip, &addr.sin_addr)

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if res == 0 {
            return true
        }

        if errno == EINPROGRESS {
            var writeFds = fd_set()
            #if os(macOS)
            writeFds.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            #endif
            let bitIdx = Int(sock) % 32
            let intIdx = Int(sock) / 32
            withUnsafeMutablePointer(to: &writeFds.fds_bits) { ptr in
                let tuplePtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Int32.self)
                tuplePtr[intIdx] |= (1 << bitIdx)
            }

            var tv = timeval(
                tv_sec: Int(timeoutSeconds),
                tv_usec: Int32((timeoutSeconds.truncatingRemainder(dividingBy: 1.0)) * 1_000_000)
            )

            let sel = select(sock + 1, nil, &writeFds, nil, &tv)
            if sel > 0 {
                var errVal: Int32 = 0
                var errLen = socklen_t(MemoryLayout<Int32>.size)
                if getsockopt(sock, SOL_SOCKET, SO_ERROR, &errVal, &errLen) == 0 && errVal == 0 {
                    return true
                }
            }
        }

        return false
    }

    public nonisolated func testTCPPort(ip: String, port: Int = 5555, timeoutSeconds: Double = 2.0) -> Bool {
        if singleProbeTCPPort(ip: ip, port: port, timeoutSeconds: timeoutSeconds) {
            return true
        }
        // Mobile Wi-Fi radios sleep periodically (DTIM). Retry once after brief pause to allow ARP resolution.
        usleep(100_000) // 100ms
        return singleProbeTCPPort(ip: ip, port: port, timeoutSeconds: timeoutSeconds)
    }

    // MARK: - Connection Actions

    public func connectTCP(ip: String, port: Int = 5555) async -> Result<String, ADBError> {
        let target = "\(ip):\(port)"
        do {
            var result = try await runCommand(["connect", target])
            var combined = (result.stdout + " " + result.stderr).lowercased()
            if combined.contains("connected to") || combined.contains("already connected to") {
                return .success(target)
            }

            // On macOS, if network routes changed, Wi-Fi reconnected, or VPN/WARP tunnels
            // altered interface routes, the background adb daemon can hold stale Darwin BSD
            // routing table caches, resulting in "No route to host" or socket failures.
            // Self-healing: Kill the stale daemon and retry with a freshly spawned server.
            _ = try? await runCommand(["kill-server"])
            try? await Task.sleep(nanoseconds: 350_000_000)

            result = try await runCommand(["connect", target])
            combined = (result.stdout + " " + result.stderr).lowercased()
            if combined.contains("connected to") || combined.contains("already connected to") {
                return .success(target)
            } else {
                return .failure(.connectionFailed(result.stdout.isEmpty ? result.stderr : result.stdout))
            }
        } catch {
            return .failure(.connectionFailed(error.localizedDescription))
        }
    }

    public func pairDevice(ip: String, port: Int, code: String) async -> Result<String, ADBError> {
        let target = "\(ip):\(port)"
        do {
            let result = try await runCommand(["pair", target, code])
            if result.stdout.contains("Successfully paired") {
                return .success(result.stdout)
            } else {
                return .failure(.connectionFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
        } catch {
            return .failure(.connectionFailed(error.localizedDescription))
        }
    }

    public func removePortForward(port: Int = 27183) async {
        _ = try? await runCommand(["forward", "--remove", "tcp:\(port)"])
    }

    public func setupPortForward(serial: String, localPort: Int = 27183, remoteAbstract: String = "scrcpy") async -> Result<Void, ADBError> {
        do {
            let result = try await runCommand(["-s", serial, "forward", "tcp:\(localPort)", "localabstract:\(remoteAbstract)"])
            if result.status == 0 {
                return .success(())
            } else {
                return .failure(.executionFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    public func pushServer(serial: String, localJarPath: String) async -> Result<Void, ADBError> {
        do {
            let result = try await runCommand(["-s", serial, "push", localJarPath, "/data/local/tmp/scrcpy-server.jar"], timeout: 15.0)
            if result.status == 0 {
                return .success(())
            } else {
                return .failure(.executionFailed(result.stderr.isEmpty ? result.stdout : result.stderr))
            }
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    // MARK: - Universal OEM Diagnostics & Wakefulness Shield

    private var cachedOEMDetails: [String: OEMDetails] = [:]

    public func fetchOEMDetails(serial: String) async -> OEMDetails {
        if let cached = cachedOEMDetails[serial] {
            return cached
        }

        let cmd = "echo M:$(getprop ro.product.manufacturer); echo B:$(getprop ro.product.brand); echo MOD:$(getprop ro.product.model); echo SDK:$(getprop ro.build.version.sdk)"
        var manufacturer = "Generic"
        var brand = "Android"
        var model = serial
        var sdk = 30

        if let res = try? await runCommand(["-s", serial, "shell", cmd], timeout: 4.0), res.status == 0 {
            for line in res.stdout.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.starts(with: "M:") {
                    let val = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { manufacturer = val }
                } else if trimmed.starts(with: "B:") {
                    let val = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { brand = val }
                } else if trimmed.starts(with: "MOD:") {
                    let val = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty { model = val }
                } else if trimmed.starts(with: "SDK:") {
                    let val = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    if let num = Int(val) { sdk = num }
                }
            }
        }

        let details = OEMDetails(manufacturer: manufacturer, brand: brand, model: model, androidSDK: sdk)
        cachedOEMDetails[serial] = details
        return details
    }

    public func wakeDeviceIfNeeded(serial: String) async {
        // Send keyevent 224 (AKEYCODE_WAKEUP) to turn on the screen so the video encoder initializes cleanly
        _ = try? await runCommand(["-s", serial, "shell", "input keyevent 224"], timeout: 3.0)
    }

    public func isScreenLocked(serial: String) async -> Bool {
        if let res = try? await runCommand(["-s", serial, "shell", "dumpsys window | grep -E 'mDreamingLockscreen=true|isStatusBarKeyguard=true'"], timeout: 3.0), res.status == 0 {
            return !res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    public nonisolated static func buildServerArguments(
        serial: String,
        mode: ConnectionMode,
        scid: Int32,
        tier: EncoderTier = .tier1_hardwareNative
    ) -> [String] {
        let scidHex = String(format: "%08x", scid)
        var serverArgs: [String] = [
            "-s", serial,
            "shell",
            "CLASSPATH=/data/local/tmp/scrcpy-server.jar",
            "app_process", "/", "com.genymobile.scrcpy.Server",
            "5.0.1",
            "scid=\(scidHex)",
            "tunnel_forward=true",
            "audio=false",
            "cleanup=false"
        ]

        switch tier {
        case .tier1_hardwareNative:
            serverArgs.append("video_bit_rate=\(mode.videoBitrate)")
            if mode.maxSize > 0 {
                serverArgs.append("max_size=\(mode.maxSize)")
                serverArgs.append("max_fps=\(mode.maxFps)")
            }

        case .tier2_hardwareAligned:
            // Safe 720p/1080p alignment with capped bitrate & 30fps
            serverArgs.append("video_bit_rate=4000000")
            serverArgs.append("max_size=1280")
            serverArgs.append("max_fps=30")

        case .tier3_universalSoftware:
            // Infallible Google AOSP software encoder fallback (Section 5.2 Android CDD mandatory)
            serverArgs.append("video_bit_rate=2000000")
            serverArgs.append("max_size=1024")
            serverArgs.append("max_fps=30")
            serverArgs.append("video_encoder=c2.android.avc.encoder")
        }

        return serverArgs
    }

    public func launchScrcpyServer(serial: String, mode: ConnectionMode, scid: Int32, tier: EncoderTier = .tier1_hardwareNative) throws -> Process {
        guard let adb = resolveADBPath() else {
            throw ADBError.adbNotFound
        }

        let serverArgs = Self.buildServerArguments(serial: serial, mode: mode, scid: scid, tier: tier)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = serverArgs

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Asynchronously drain the pipe to prevent buffer deadlocks
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("[scrcpy-server] \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
                #endif
            }
        }

        try process.run()
        return process
    }

    public func installAPK(serial: String, apkPath: String) async -> Result<String, ADBError> {
        do {
            let res = try await runCommand(["-s", serial, "install", "-r", apkPath], timeout: 60.0)
            if res.status == 0 && res.stdout.contains("Success") {
                return .success(res.stdout)
            } else {
                return .failure(.executionFailed(res.stderr.isEmpty ? res.stdout : res.stderr))
            }
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    public func pushFile(serial: String, localPath: String, remotePath: String = "/sdcard/Download/") async -> Result<String, ADBError> {
        do {
            let res = try await runCommand(["-s", serial, "push", localPath, remotePath], timeout: 60.0)
            if res.status == 0 {
                return .success("Pushed to \(remotePath)")
            } else {
                return .failure(.executionFailed(res.stderr.isEmpty ? res.stdout : res.stderr))
            }
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }
}

public nonisolated func isValidIPv4(_ str: String) -> Bool {
    var sin = sockaddr_in()
    return str.withCString { cstr in
        inet_pton(AF_INET, cstr, &sin.sin_addr) == 1
    }
}
