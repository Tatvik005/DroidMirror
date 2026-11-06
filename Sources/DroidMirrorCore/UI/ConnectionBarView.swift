import SwiftUI

public struct ConnectionBarView: View {
    @ObservedObject var transport: TransportManager

    public init(transport: TransportManager) {
        self.transport = transport
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Top Row: 3 Mode Buttons + Multi-Device Selector + Status Pill
            HStack(spacing: 10) {
                // 3 Explicit Connection Mode Buttons
                HStack(spacing: 6) {
                    ForEach(ConnectionMode.allCases) { mode in
                        ModeSelectorButton(
                            mode: mode,
                            isSelected: transport.selectedMode == mode,
                            isActive: transport.activeMode == mode && transport.isConnected,
                            action: {
                                transport.selectMode(mode)
                            }
                        )
                    }
                }

                // Universal Multi-Device Selector (Visible when 2+ devices are attached)
                if transport.allDetectedDevices.count > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Picker("", selection: Binding(
                            get: { transport.selectedDeviceSerial },
                            set: { newSerial in
                                transport.selectDevice(bySerial: newSerial)
                            }
                        )) {
                            ForEach(transport.allDetectedDevices) { dev in
                                Text(dev.displayName).tag(dev.serial)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 240)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .help("Select target phone from detected devices")
                }

                Spacer()

                // OEM Compatibility Pill
                if let oem = transport.activeOEMDetails, transport.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text(oem.brandDisplayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                }

                // Fallback Encoder Indicator
                if transport.currentEncoderTier != .tier1_hardwareNative && transport.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("Tier \(transport.currentEncoderTier.rawValue)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                    .help(transport.currentEncoderTier.description)
                }

                // Live Status Pill
                StatusPillView(transport: transport)

                if transport.isConnected {
                    Button(action: {
                        transport.toggleFloatingWindow()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pip.enter")
                                .foregroundColor(.purple)
                            Text("Floating Window")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .help("Shrink to compact phone-sized floating window (⇧⌘F)")
                }

                // Help & Guide Button
                Button(action: {
                    transport.showHelpModal = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Help & Guide")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Open Switch Guide & Help (⌘?)")
            }

            // Bottom Row: Contextual Configuration Bar
            HStack(spacing: 12) {
                switch transport.selectedMode {
                case .usb:
                    usbContextualBar
                case .homeWiFi:
                    wifiContextualBar
                case .phoneHotspot:
                    phoneHotspotContextualBar
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - USB Context Bar

    private var usbContextualBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .foregroundColor(.blue)

            if transport.detectedUSBDevices.isEmpty {
                Text("No USB devices detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if transport.detectedUSBDevices.count == 1, let dev = transport.detectedUSBDevices.first {
                Text("Target: \(dev.displayName)")
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Picker("Target:", selection: $transport.usbDeviceSerial) {
                    ForEach(transport.detectedUSBDevices) { dev in
                        Text(dev.displayName).tag(dev.serial)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }

            Button(action: {
                Task { await transport.refreshUSBDevices() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh USB Devices")

            Spacer()

            // Prep for Wireless Helper Button
            Button(action: {
                Task { await transport.enableTCPIPOverUSB() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "network.badge.shield.half.filled")
                    Text("Prep for Wireless (Enable Port 5555)")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Enables adb tcpip 5555 so phone can be unplugged and used wirelessly")

            // Connect Button
            Button(action: {
                Task { await transport.applySelectedMode() }
            }) {
                if transport.isPreflighting || transport.isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(transport.activeMode == .usb && transport.isConnected ? "Re-connect USB" : "Connect via USB")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(transport.isPreflighting || transport.isConnecting)
        }
    }

    // MARK: - Wi-Fi Context Bar

    private var wifiContextualBar: some View {
        let wifiDevices = transport.allDetectedDevices.filter { $0.isWiFi }

        return HStack(spacing: 10) {
            Image(systemName: "wifi")
                .foregroundColor(.green)

            if wifiDevices.count > 1 {
                Picker("Target:", selection: Binding(
                    get: {
                        wifiDevices.first(where: { $0.serial.hasPrefix(transport.wifiInputIP) })?.serial ?? transport.wifiInputIP
                    },
                    set: { newSerial in
                        let ipPart = String(newSerial.split(separator: ":")[0])
                        transport.wifiInputIP = ipPart
                        transport.selectedDeviceSerial = newSerial
                    }
                )) {
                    ForEach(wifiDevices) { dev in
                        Text(dev.displayName).tag(dev.serial)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            } else {
                Text("Phone LAN IP:")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("192.168.1.xxx", text: $transport.wifiInputIP)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 140)

            Button(action: {
                Task { await transport.refreshContextForSelectedMode() }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                    Text("Detect IP")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Auto-detect IP address using USB if attached")

            Button(action: {
                transport.showPairingModal = true
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "qrcode")
                    Text("Pair (Android 11+)")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Pair with Android 11+ Wireless Debugging code")

            Spacer()

            Button(action: {
                Task { await transport.applySelectedMode() }
            }) {
                if transport.isPreflighting || transport.isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect & Switch")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(transport.isPreflighting || transport.isConnecting || transport.wifiInputIP.isEmpty)
        }
    }

    // MARK: - Phone Hotspot Context Bar

    private var phoneHotspotContextualBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "personalhotspot")
                .foregroundColor(.orange)

            Text("Gateway IP (Phone AP):")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("192.168.43.1", text: $transport.phoneHotspotInputIP)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 150)

            Button(action: {
                Task { await transport.refreshContextForSelectedMode() }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                    Text("Detect Gateway")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Queries Mac default route gateway IP")

            Text("Mac is connected to Phone's Wi-Fi hotspot")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                Task { await transport.applySelectedMode() }
            }) {
                if transport.isPreflighting || transport.isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect & Switch")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(transport.isPreflighting || transport.isConnecting || transport.phoneHotspotInputIP.isEmpty)
        }
    }
}

// MARK: - Mode Button Subview

private struct ModeSelectorButton: View {
    let mode: ConnectionMode
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive ? .green : (isSelected ? .accentColor : .secondary))

                Text(mode.shortTitle)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)

                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
