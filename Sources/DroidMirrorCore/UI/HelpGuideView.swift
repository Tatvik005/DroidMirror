import SwiftUI

final class HelpGuideState: ObservableObject {
    @Published var selectedTab: HelpGuideView.HelpSection = .allSwitches
}

public struct HelpGuideView: View {
    @ObservedObject var transport: TransportManager
    @StateObject private var state = HelpGuideState()

    public enum HelpSection: String, CaseIterable, Identifiable {
        case allSwitches = "The 3 Switches"
        case switch2DifferentWifi = "Switch 2: Different Wi-Fi"
        case universalOEM = "Universal Phone Guide"
        case switch1USB = "1. Wired USB"
        case switch2HomeWifi = "2. Home Wi-Fi"
        case switch3PhoneHotspot = "3. Phone Hotspot"
        case troubleshooting = "Troubleshooting & VPN"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .allSwitches: return "rectangle.grid.3x1"
            case .switch2DifferentWifi: return "arrow.triangle.swap"
            case .universalOEM: return "iphone.gen3"
            case .switch1USB: return "cable.connector"
            case .switch2HomeWifi: return "wifi"
            case .switch3PhoneHotspot: return "personalhotspot"
            case .troubleshooting: return "wrench.and.screwdriver"
            }
        }
    }

    public init(transport: TransportManager) {
        self.transport = transport
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DroidMirror Switch Guide & Reference")
                        .font(.headline)
                    Text("Deterministic Button-Driven Connection Modes & Wi-Fi Switching")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    transport.showHelpModal = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Content: Sidebar + Detail
            HSplitView {
                // Sidebar Navigation
                List(HelpSection.allCases, id: \.self, selection: $state.selectedTab) { section in
                    HStack(spacing: 8) {
                        Image(systemName: section.iconName)
                            .foregroundColor(section == .switch2DifferentWifi ? .orange : .accentColor)
                            .frame(width: 18)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: section == .switch2DifferentWifi ? .semibold : .regular))
                    }
                    .padding(.vertical, 3)
                    .tag(section)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 200, maxWidth: 230)

                // Detail View
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch state.selectedTab {
                        case .allSwitches:
                            allSwitchesOverviewView
                        case .switch2DifferentWifi:
                            differentWifiGuideView
                        case .universalOEM:
                            universalOEMGuideView
                        case .switch1USB:
                            switch1USBView
                        case .switch2HomeWifi:
                            switch2HomeWifiView
                        case .switch3PhoneHotspot:
                            switch3PhoneHotspotView
                        case .troubleshooting:
                            troubleshootingView
                        }
                    }
                    .padding(24)
                }
                .frame(minWidth: 500, maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }

            Divider()

            // Footer Bar
            HStack {
                Text("Press Esc or click Done to close this guide")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Done") {
                    transport.showHelpModal = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 780, height: 560)
    }

    // MARK: - Section Views

    // 1. All 3 Switches Overview
    private var allSwitchesOverviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("The 3 Deterministic Switches", icon: "rectangle.grid.3x1", color: .blue)

            Text("To avoid network race conditions and accidental disconnections, DroidMirror NEVER switches connections automatically in the background. You explicitly control which physical path carries your stream by clicking its button.")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                switchCard(
                    number: "1",
                    title: "Wired USB Cable",
                    badge: "16 Mbps · 0 Latency",
                    badgeColor: .blue,
                    icon: "cable.connector",
                    summary: "Uncompressed direct stream. Lowest latency. Use this initially to enable Port 5555 for wireless modes.",
                    mode: .usb
                )

                switchCard(
                    number: "2",
                    title: "Standard Home Wi-Fi",
                    badge: "Convenient · 1600p 60fps",
                    badgeColor: .green,
                    icon: "wifi",
                    summary: "Connects over your local Wi-Fi router. Supports manual IP override and Android 11+ wireless pairing.",
                    mode: .homeWiFi
                )

                switchCard(
                    number: "3",
                    title: "Offline Phone Hotspot",
                    badge: "Field Work · No Router",
                    badgeColor: .orange,
                    icon: "personalhotspot",
                    summary: "Turn on phone's hotspot, join Mac to it. DroidMirror auto-detects the phone's gateway IP (e.g. 192.168.43.1).",
                    mode: .phoneHotspot
                )
            }
        }
    }

    // 2. High Priority: How to connect to a different Wi-Fi in Switch 2
    private var differentWifiGuideView: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideTitle("How to Connect to a Different Wi-Fi Network (Switch 2)", icon: "arrow.triangle.swap", color: .orange)

            calloutBox(
                icon: "info.circle.fill",
                title: "Why does the IP change?",
                message: "Every Wi-Fi router assigns a unique local IP address (e.g. moving from 192.168.31.247 to 192.168.1.55). Because TCP sockets cannot survive an IP change, you simply enter the new IP and click 'Connect & Switch'.",
                color: .blue
            )

            Text("3 Easy Steps to Switch Wi-Fi Networks:")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(
                    step: "1",
                    title: "Connect Both Devices to the New Wi-Fi",
                    description: "Join both your Mac and your Android phone to the new Wi-Fi router (must be the same network)."
                )

                stepRow(
                    step: "2",
                    title: "Find Your Phone's New IP Address",
                    description: "On your phone:\n• Samsung/OneUI: Settings → About Phone → Status Information → IP address\n• Pixel/Stock Android: Settings → Network & internet → Internet → tap your Wi-Fi name → scroll to IP address."
                )

                stepRow(
                    step: "3",
                    title: "Enter IP in DroidMirror & Click 'Connect & Switch'",
                    description: "In DroidMirror, select 'Home Wi-Fi', paste or type the new IP into the 'Phone LAN IP' field, and click 'Connect & Switch'."
                )
            }

            Divider()

            Text("Do I need to plug the USB cable in again?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("NO CABLE NEEDED (If phone was not restarted):")
                        .fontWeight(.semibold)
                }
                Text("Android's ADB daemon keeps Port 5555 open across any Wi-Fi network switches. As long as your phone was not powered off or rebooted, simply typing the new IP will connect instantly.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("If the phone was rebooted:")
                        .fontWeight(.semibold)
                }
                Text("Rebooting closes Port 5555. You have two fast ways to re-enable it:\n1. Wireless: Use the built-in 'Pair (Android 11+)' button with Wireless Debugging (no cable required!).\n2. USB: Plug the cable for 1 second, tap 'Prep for Wireless (Enable Port 5555)', and unplug.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
            }
        }
    }

    // 3. Switch 1: Wired USB
    private var switch1USBView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("Switch 1: Wired USB Mode", icon: "cable.connector", color: .blue)

            calloutBox(
                icon: "bolt.fill",
                title: "Ultra Performance Profile",
                message: "16 Mbps bitrate, native display resolution, and zero buffer queue for lowest latency.",
                color: .green
            )

            Text("Step-by-Step Instructions:")
                .font(.headline)

            stepRow(step: "1", title: "Enable USB Debugging on Phone", description: "Settings → Developer Options → Turn ON 'USB Debugging'.")
            stepRow(step: "2", title: "Connect via USB-C Cable", description: "Plug your phone into your Mac. If prompted on the phone, check 'Always allow from this computer' and tap Allow.")
            stepRow(step: "3", title: "Select 'Wired USB' & Click 'Connect via USB'", description: "Your phone serial will appear automatically in the target bar.")

            Divider()

            calloutBox(
                icon: "network.badge.shield.half.filled",
                title: "Golden Step: 'Prep for Wireless'",
                message: "While connected over USB, click the 'Prep for Wireless (Enable Port 5555)' button. This unlocks Wi-Fi and Hotspot modes so you can disconnect the cable whenever you want!",
                color: .blue
            )
        }
    }

    // 4. Switch 2: Home Wi-Fi
    private var switch2HomeWifiView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("Switch 2: Standard Home Wi-Fi Mode", icon: "wifi", color: .green)

            Text("Stream wirelessly through your local home or office router at 6 Mbps (1600p max resolution @ 60 FPS).")
                .foregroundColor(.secondary)

            Text("Three Ways to Connect:")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Text("A")
                        .font(.headline)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Detect via USB First (Fastest)")
                            .fontWeight(.semibold)
                        Text("With phone on USB, click 'Detect IP' to auto-populate phone LAN IP, click 'Prep for Wireless', unplug USB, and click 'Connect & Switch'.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("B")
                        .font(.headline)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual IP Entry")
                            .fontWeight(.semibold)
                        Text("Check your phone's Wi-Fi IP in Settings, type it in the text field, and click 'Connect & Switch'. DroidMirror tests reachability before switching.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Text("C")
                        .font(.headline)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("100% Wire-Free Android 11+ Pairing")
                            .fontWeight(.semibold)
                        Text("Enable 'Wireless Debugging' in Developer Options, tap 'Pair device with pairing code', and click DroidMirror's 'Pair (Android 11+)' button.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // 5. Switch 3: Phone Hotspot
    private var switch3PhoneHotspotView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("Switch 3: Offline Phone Hotspot Mode", icon: "personalhotspot", color: .orange)

            calloutBox(
                icon: "airplane",
                title: "Best for Travel & Field Work",
                message: "Does NOT require an external Wi-Fi router or home internet. The phone creates the Wi-Fi network and the Mac connects directly to it.",
                color: .orange
            )

            Text("Step-by-Step Instructions:")
                .font(.headline)

            stepRow(step: "1", title: "Enable Mobile Hotspot on Phone", description: "Turn on 'Personal Hotspot' / 'Mobile Hotspot' in your Android settings.")
            stepRow(step: "2", title: "Connect Mac to Phone's Hotspot", description: "In macOS Wi-Fi menu, select your phone's Wi-Fi network and enter the password.")
            stepRow(step: "3", title: "Click Switch 3: [Phone Hotspot]", description: "DroidMirror queries your Mac default route and automatically finds the phone's gateway IP (usually 192.168.43.1).")
            stepRow(step: "4", title: "Click 'Connect & Switch'", description: "Starts a peer-to-peer 6 Mbps stream bypassing any router isolation.")
        }
    }

    // 6. Troubleshooting
    private var troubleshootingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("Troubleshooting & Pro Features", icon: "wrench.and.screwdriver", color: .red)

            calloutBox(
                icon: "pip.enter",
                title: "Compact Floating Phone Window (⇧⌘F)",
                message: "Once connected, click 'Floating Window' in the top bar, the side toolbar icon, or press Shift+Cmd+F. DroidMirror shrinks to the exact size of your phone and stays floating on top of your work. You can operate the phone with touch, gestures, and typing just like before without taking up screen space.",
                color: .purple
            )

            calloutBox(
                icon: "shield.slash.fill",
                title: "VPN & Cloudflare WARP/Zero Trust ('No route to host')",
                message: "If Cloudflare One, WARP, Cisco AnyConnect, or Tailscale is active on your Mac, it may capture local private IP ranges (192.168.x.x). In your VPN client, enable 'Local Network Fallback' / 'Exclude Local Subnets', or temporarily pause the VPN.",
                color: .orange
            )

            calloutBox(
                icon: "lock.shield.fill",
                title: "Public / Hotel Wi-Fi (AP Client Isolation)",
                message: "Many hotel, airport, and university Wi-Fi networks block devices from communicating with each other. If port 5555 fails on public Wi-Fi, switch to Method 3 (Phone Hotspot) which completely bypasses the hotel router.",
                color: .blue
            )

            calloutBox(
                icon: "bolt.horizontal.fill",
                title: "Self-Healing Daemon Recovery",
                message: "DroidMirror automatically detects stale macOS Darwin socket routing caches. If an ADB connection fails due to route changes, DroidMirror restarts the ADB server in the background and retries automatically.",
                color: .green
            )
        }
    }

    // MARK: - Helper UI Builders

    private func guideTitle(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(text)
                .font(.title2)
                .fontWeight(.bold)
        }
    }

    private func switchCard(number: String, title: String, badge: String, badgeColor: Color, icon: String, summary: String, mode: ConnectionMode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(badgeColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(badgeColor)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .foregroundColor(badgeColor)
                        .cornerRadius(4)
                }

                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Select \(title)") {
                    transport.selectMode(mode)
                    transport.showHelpModal = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func stepRow(step: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func calloutBox(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.85))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Universal OEM Smartphone Guide

    private var universalOEMGuideView: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideTitle("Universal Smartphone Compatibility", icon: "iphone.gen3", color: .purple)

            Text("DroidMirror is engineered to work reliably on all Android smartphones from Android 5.0 through Android 15/16. Different manufacturers have specific developer and security settings:")
                .font(.body)
                .foregroundColor(.secondary)

            // 1. Samsung Galaxy
            oemCard(
                title: "Samsung Galaxy (OneUI 5 / 6 / 7)",
                icon: "shield.lefthalf.filled",
                color: .blue,
                tips: [
                    "Knox Lockscreen Protection: While the phone is locked with a PIN or pattern, Knox blanks video output to protect privacy. You can type your PIN directly on your Mac keyboard and press Enter to unlock the screen immediately.",
                    "Auto Blocker: On newer OneUI versions, Auto Blocker (in Settings > Security) can prevent ADB commands. If adb fails to connect, allow USB debugging in Auto Blocker settings.",
                    "Command-Line Stack Canary: DroidMirror automatically protects Samsung's 256-byte stack buffer in libsfplugin_ccodec.so so hardware decoding runs without crashes."
                ]
            )

            // 2. Xiaomi, Redmi & POCO
            oemCard(
                title: "Xiaomi / Redmi / POCO (HyperOS / MIUI)",
                icon: "hand.tap.fill",
                color: .orange,
                tips: [
                    "Touch & Typing Permission: Xiaomi disables simulated touches by default. You MUST enable 'USB debugging (Security settings)' in Developer Options. (Requires an active SIM card to toggle once).",
                    "MIUI Optimization: Keep enabled unless installing custom split APKs.",
                    "Turn on 'Install via USB' if pushing APKs through DroidMirror drag-and-drop."
                ]
            )

            // 3. OPPO, OnePlus & Realme
            oemCard(
                title: "OPPO / OnePlus / Realme (ColorOS / OxygenOS)",
                icon: "bolt.horizontal.fill",
                color: .red,
                tips: [
                    "OTG Connection Timeout: ColorOS automatically turns off OTG after 10 minutes. If USB drops, re-enable 'OTG connection' in Additional Settings.",
                    "Disable Permission Monitoring: Enable 'Developer options > Disable permission monitoring' if touch events or dialog clicks are ignored.",
                    "Turn on 'Allow ADB debugging in charge only mode' for seamless wireless switching."
                ]
            )

            // 4. Vivo & iQOO
            oemCard(
                title: "Vivo & iQOO (FuntouchOS / OriginOS)",
                icon: "touchid",
                color: .cyan,
                tips: [
                    "Input Simulation: Enable 'USB debugging' and 'Input simulation' (or 'USB debugging (Security settings)') in Developer options.",
                    "Default USB Configuration: Set to 'File Transfer (MTP)' rather than 'Charge only'."
                ]
            )

            // 5. Google Pixel, Motorola, Nothing & Sony
            oemCard(
                title: "Google Pixel / Motorola / Nothing (Stock AOSP)",
                icon: "checkmark.seal.fill",
                color: .green,
                tips: [
                    "Universal Zero-Configuration: Works immediately with standard 'USB debugging'.",
                    "Android 11+ Wireless Debugging: Supports pairing codes without USB cable. Use the 'Pair (Android 11+)' button in Switch 2."
                ]
            )

            // 6. Multi-Tier Codec Auto-Recovery
            oemCard(
                title: "Budget & Legacy Devices (MediaTek / Unisoc)",
                icon: "cpu",
                color: .indigo,
                tips: [
                    "Tier 1 (Default): High-performance native hardware H.264.",
                    "Tier 2 (Safe Alignment): If a budget chipset fails at high bitrates or unaligned resolutions, DroidMirror automatically falls back to 1280px / 30 FPS.",
                    "Tier 3 (Universal AOSP Software): Infallible fallback using Google's certified c2.android.avc.encoder, guaranteed to work on 100% of certified Android phones."
                ]
            )
        }
    }

    private func oemCard(title: String, icon: String, color: Color, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(color)
                            .font(.system(size: 12, weight: .bold))
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}
