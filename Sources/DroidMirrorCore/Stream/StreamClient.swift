import Foundation
import Darwin

public enum StreamClientError: LocalizedError {
    case connectionFailed(String)
    case socketError(String)
    case handshakeFailed(String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Failed to connect to stream socket: \(msg)"
        case .socketError(let msg): return "Socket error: \(msg)"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .disconnected: return "Socket disconnected"
        }
    }
}

public final class POSIXSocket {
    private var fd: Int32 = -1
    private let lock = NSLock()

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fd >= 0
    }

    public init() {}

    public func connect(host: String = "127.0.0.1", port: Int = 27183) throws {
        lock.lock()
        defer { lock.unlock() }

        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }

        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else {
            throw StreamClientError.socketError("socket() failed: \(errno)")
        }

        // Enable TCP_NODELAY to bypass Nagle's algorithm for minimal latency
        var yes: Int32 = 1
        setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &addr.sin_addr)

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard res == 0 else {
            Darwin.close(sock)
            throw StreamClientError.connectionFailed("connect() to \(host):\(port) failed with errno \(errno)")
        }

        self.fd = sock
    }

    public func readExact(count: Int) throws -> Data {
        var data = Data(count: count)
        var totalRead = 0

        while totalRead < count {
            let currentFD: Int32
            lock.lock()
            currentFD = self.fd
            lock.unlock()

            guard currentFD >= 0 else {
                throw StreamClientError.disconnected
            }

            let bytesRead = data.withUnsafeMutableBytes { rawPtr in
                Darwin.read(currentFD, rawPtr.baseAddress!.advanced(by: totalRead), count - totalRead)
            }

            if bytesRead > 0 {
                totalRead += bytesRead
            } else if bytesRead == 0 {
                throw StreamClientError.disconnected
            } else {
                if errno == EINTR { continue }
                throw StreamClientError.socketError("read() failed: errno \(errno)")
            }
        }

        return data
    }

    public func write(_ data: Data) throws {
        var totalWritten = 0
        let count = data.count

        while totalWritten < count {
            let currentFD: Int32
            lock.lock()
            currentFD = self.fd
            lock.unlock()

            guard currentFD >= 0 else {
                throw StreamClientError.disconnected
            }

            let bytesWritten = data.withUnsafeBytes { rawPtr in
                Darwin.write(currentFD, rawPtr.baseAddress!.advanced(by: totalWritten), count - totalWritten)
            }

            if bytesWritten > 0 {
                totalWritten += bytesWritten
            } else {
                if errno == EINTR { continue }
                throw StreamClientError.socketError("write() failed: errno \(errno)")
            }
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
            fd = -1
        }
    }
}

public final class StreamClient {
    public let videoSocket = POSIXSocket()
    public let controlSocket = POSIXSocket()

    public private(set) var deviceName: String = ""
    public private(set) var currentResolution: (width: Int, height: Int) = (0, 0)
    public private(set) var isRunning: Bool = false

    public var onHandshakeCompleted: ((String, (Int, Int)) -> Void)?
    public var onResolutionChanged: ((Int, Int) -> Void)?
    public var onDisconnected: ((Error?) -> Void)?

    private var videoThread: Thread?
    private var controlThread: Thread?
    private let decoder: H264Decoder
    private let controlInjector: ControlInjector

    public init(decoder: H264Decoder, controlInjector: ControlInjector = .shared) {
        self.decoder = decoder
        self.controlInjector = controlInjector
    }

    /// Robust connection matching official scrcpy connect_to_server retry loop.
    /// Retries connecting both video and control sockets until server accepts and emits dummy byte.
    public func connect(port: Int = 27183, maxAttempts: Int = 50, delayMs: UInt64 = 100) throws {
        disconnect()

        var connected = false
        var attemptsLeft = maxAttempts

        while attemptsLeft > 0 && !connected {
            attemptsLeft -= 1
            do {
                // 1. Connect Video Socket
                try videoSocket.connect(host: "127.0.0.1", port: port)

                // 2. Connect Control Socket (scrcpy-server blocks on accept() until Socket 2 connects)
                try controlSocket.connect(host: "127.0.0.1", port: port)

                // 3. Test reachability by reading dummy byte (0x00) emitted on Socket 1
                let dummy = try videoSocket.readExact(count: 1)
                guard dummy.count == 1 else {
                    throw StreamClientError.handshakeFailed("Invalid dummy byte")
                }
                connected = true
            } catch {
                videoSocket.close()
                controlSocket.close()
                if attemptsLeft > 0 {
                    usleep(useconds_t(delayMs * 1000))
                }
            }
        }

        guard connected else {
            throw StreamClientError.connectionFailed("Could not connect to scrcpy forward socket after \(maxAttempts) attempts.")
        }

        // Read handshake metadata on Video Socket
        let nameData = try videoSocket.readExact(count: 64)
        let name = String(data: nameData.prefix(while: { $0 != 0 }), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Android Device"
        self.deviceName = name

        let codecData = try videoSocket.readExact(count: 4)
        let codecId = String(data: codecData, encoding: .utf8) ?? "h264"
        _ = codecId

        isRunning = true

        // Wire up control injector to Socket 2
        controlInjector.sendDataHandler = { [weak self] data in
            guard let self = self, self.isRunning else { return }
            try? self.controlSocket.write(data)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onHandshakeCompleted?(self.deviceName, self.currentResolution)
        }

        // Start reading threads
        startVideoDemuxerThread()
        startControlReaderThread()

        // Force an immediate IDR keyframe from the device video encoder
        try? controlSocket.write(Data([17])) // TYPE_RESET_VIDEO
    }

    public func disconnect() {
        guard isRunning || videoSocket.isConnected || controlSocket.isConnected else { return }
        isRunning = false

        controlInjector.sendDataHandler = nil
        videoSocket.close()
        controlSocket.close()

        videoThread?.cancel()
        controlThread?.cancel()
        videoThread = nil
        controlThread = nil
    }

    private func startVideoDemuxerThread() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            do {
                try self.runVideoLoop()
            } catch {
                if self.isRunning {
                    DispatchQueue.main.async {
                        self.onDisconnected?(error)
                    }
                }
            }
        }
        thread.name = "com.droidmirror.video.demuxer"
        thread.qualityOfService = .userInteractive
        videoThread = thread
        thread.start()
    }

    private func runVideoLoop() throws {
        while isRunning {
            let header = try videoSocket.readExact(count: 12)

            // Check if packet is a Session metadata packet (flags with MSB = 1)
            let firstWord = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let isSessionPacket = (firstWord & 0x80000000) != 0

            if isSessionPacket {
                // Session Packet: [flags: 4B, width: 4B, height: 4B]
                let width = Int(header.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                let height = Int(header.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                self.currentResolution = (width, height)
                decoder.updateDimensions(width: width, height: height)
                DispatchQueue.main.async { [weak self] in
                    self?.onResolutionChanged?(width, height)
                }
                continue
            }

            // Media Frame Packet: [ptsAndFlags: 8B, packetSize: 4B]
            let ptsAndFlags = header.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            let packetSize = Int(header.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })

            let isConfig = (ptsAndFlags & (1 << 62)) != 0
            let isKeyFrame = (ptsAndFlags & (1 << 61)) != 0
            let ptsUs = Int64(ptsAndFlags & 0x1FFFFFFFFFFFFFFF)

            guard packetSize > 0 && packetSize < 10_000_000 else {
                throw StreamClientError.socketError("Invalid packet size: \(packetSize)")
            }

            let framePayload = try videoSocket.readExact(count: packetSize)
            decoder.decodeAndDisplay(packet: framePayload, ptsUs: ptsUs, isConfig: isConfig, isKeyFrame: isKeyFrame)
        }
    }

    private func startControlReaderThread() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            do {
                try self.runControlLoop()
            } catch {
                // Control reader ended
            }
        }
        thread.name = "com.droidmirror.control.reader"
        thread.qualityOfService = .userInitiated
        controlThread = thread
        thread.start()
    }

    private func runControlLoop() throws {
        while isRunning {
            let typeData = try controlSocket.readExact(count: 1)
            let msgType = typeData[0]

            if msgType == 0 { // TYPE_CLIPBOARD
                let lenData = try controlSocket.readExact(count: 4)
                let textLen = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                if textLen > 0 && textLen < 500_000 {
                    let textData = try controlSocket.readExact(count: textLen)
                    var fullMsg = Data([msgType])
                    fullMsg.append(lenData)
                    fullMsg.append(textData)
                    controlInjector.handleDeviceMessage(data: fullMsg)
                }
            } else if msgType == 1 { // TYPE_ACK_CLIPBOARD
                _ = try controlSocket.readExact(count: 8) // sequence
            } else if msgType == 2 { // TYPE_UHID_OUTPUT
                let idData = try controlSocket.readExact(count: 2)
                _ = idData
                let lenData = try controlSocket.readExact(count: 2)
                let len = Int(lenData.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                if len > 0 {
                    _ = try controlSocket.readExact(count: len)
                }
            }
        }
    }
}
