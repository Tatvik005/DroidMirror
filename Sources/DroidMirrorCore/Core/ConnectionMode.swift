import Foundation

/// Explicit connection modes supported by DroidMirror Mac.
/// Background automatic transport switching is deliberately disallowed to avoid network race conditions.
public enum ConnectionMode: String, CaseIterable, Identifiable {
    case usb = "Wired USB"
    case homeWiFi = "Standard Home Wi-Fi"
    case phoneHotspot = "Offline Phone Hotspot"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .usb:
            return "cable.connector"
        case .homeWiFi:
            return "wifi"
        case .phoneHotspot:
            return "personalhotspot"
        }
    }

    public var shortTitle: String {
        switch self {
        case .usb: return "USB Cable"
        case .homeWiFi: return "Home Wi-Fi"
        case .phoneHotspot: return "Phone Hotspot"
        }
    }

    public var subtitle: String {
        switch self {
        case .usb:
            return "Lowest latency, maximum bitrate (16 Mbps, native resolution)"
        case .homeWiFi:
            return "Local network IP connection via port 5555"
        case .phoneHotspot:
            return "Phone acts as AP; connects to phone's default gateway IP"
        }
    }

    /// Video encoding profile tailored to the physical medium.
    public var videoBitrate: Int {
        switch self {
        case .usb:
            return 16_000_000 // 16 Mbps
        case .homeWiFi, .phoneHotspot:
            return 6_000_000  // 6 Mbps
        }
    }

    public var maxSize: Int {
        switch self {
        case .usb:
            return 0 // Native resolution
        case .homeWiFi, .phoneHotspot:
            return 1600 // Optimized for wireless stability
        }
    }

    public var maxFps: Int {
        return 60
    }
}
