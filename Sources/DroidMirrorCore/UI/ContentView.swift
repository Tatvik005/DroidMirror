import SwiftUI

public struct ContentView: View {
    @StateObject private var transport = TransportManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if !transport.isFloatingWindow {
                // 1. Connection Mode Selector & Context Bar
                ConnectionBarView(transport: transport)

                // 2. Alert Banner (Non-modal descriptive warnings)
                if let alert = transport.alertBanner {
                    alertBannerView(message: alert)
                }

                Divider()
            }

            // 3. Main Stage: Mirror View with Empty State Placeholder Overlay
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                // VideoRendererView is always mounted so decoder.displayLayer is ready from frame zero
                VideoRendererView(
                    decoder: transport.decoder,
                    dimensions: transport.resolution,
                    onFileDropped: { url in
                        transport.handleDroppedFile(url)
                    }
                )
                .aspectRatio(aspectRatio, contentMode: .fit)
                .opacity(transport.isConnected ? 1.0 : 0.0)

                // Authentic Smartphone Hardware Bezel Accents (Camera Notch & Home Bar)
                if transport.isFloatingWindow {
                    VStack {
                        // Top Camera Punch-Hole & Speaker Earpiece
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: 44, height: 7)
                            .overlay(
                                Circle()
                                    .fill(Color(white: 0.28))
                                    .frame(width: 3.5, height: 3.5)
                                    .padding(.trailing, 24)
                            )
                            .padding(.top, 5)

                        Spacer()

                        // Bottom Home Indicator Bar
                        Capsule()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 60, height: 3)
                            .padding(.bottom, 6)
                    }
                    .allowsHitTesting(false)
                }

                // Controls Overlay
                if transport.isConnected {
                    if transport.isFloatingWindow {
                        // Compact Floating Phone Header Overlay
                        floatingWindowHeaderOverlay
                    } else {
                        // Floating Side Control Toolbar
                        HStack {
                            Spacer()
                            FloatingToolbarView(transport: transport)
                                .padding(.trailing, 16)
                        }
                        .transition(.opacity)
                    }
                }

                // Empty State / Welcome Guide (Overlaid when not connected)
                if !transport.isConnected {
                    emptyStateView
                        .background(Color.black.opacity(0.92))
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: transport.isFloatingWindow ? 34 : 0, style: .continuous))
            .overlay(
                Group {
                    if transport.isFloatingWindow {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.12),
                                        Color.black.opacity(0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                    }
                }
            )
            .shadow(color: Color.black.opacity(transport.isFloatingWindow ? 0.45 : 0.0), radius: transport.isFloatingWindow ? 18 : 0, x: 0, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: transport.isConnected)

            if !transport.isFloatingWindow {
                Divider()

                // 4. Bottom Footer Status Strip
                footerStatusStrip
            }
        }
        .frame(
            minWidth: transport.isFloatingWindow ? 240 : 840,
            maxWidth: transport.isFloatingWindow ? 300 : .infinity,
            minHeight: transport.isFloatingWindow ? 480 : 680,
            maxHeight: transport.isFloatingWindow ? 580 : .infinity
        )
        .sheet(isPresented: $transport.showPairingModal) {
            WirelessPairingModal(transport: transport)
        }
        .sheet(isPresented: $transport.showHelpModal) {
            HelpGuideView(transport: transport)
        }
        .onAppear {
            Task {
                await transport.refreshUSBDevices()
            }
        }
    }

    // MARK: - Aspect Ratio Calculation

    private var aspectRatio: CGFloat {
        if transport.resolution.width > 0 && transport.resolution.height > 0 {
            return CGFloat(transport.resolution.width) / CGFloat(transport.resolution.height)
        }
        return 9.0 / 16.0 // Standard mobile portrait default
    }

    // MARK: - Floating Compact Phone Header Overlay

    private var floatingWindowHeaderOverlay: some View {
        VStack {
            HStack(spacing: 8) {
                // Live FPS Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(transport.fps) FPS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.65))
                .cornerRadius(10)

                Spacer()

                // Quick Navigation Controls: Back, Home, Rotate, Power
                HStack(spacing: 4) {
                    floatingCompactButton(icon: "chevron.backward", help: "Back (⌘[ or Right-Click)") {
                        transport.back()
                    }
                    floatingCompactButton(icon: "circle.circle", help: "Home (⌃⌘H or Middle-Click)") {
                        transport.home()
                    }
                    floatingCompactButton(icon: "arrow.triangle.2.circlepath", help: "Rotate Phone") {
                        transport.toggleDeviceRotation()
                    }
                    floatingCompactButton(icon: "power", help: "Power (⌃⌘P)") {
                        transport.togglePower()
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.65))
                .cornerRadius(12)

                // Expand back to Normal Window
                Button(action: {
                    transport.toggleFloatingWindow()
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Exit Floating Phone Window (⇧⌘F)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)

            Spacer()
        }
    }

    private func floatingCompactButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Alert Banner View

    private func alertBannerView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            if message.contains("5555") && transport.selectedMode != .usb {
                Button(action: {
                    transport.selectMode(.usb)
                }) {
                    Text("Switch to USB & Enable 5555")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Button(action: {
                transport.alertBanner = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                if let iconImage = loadAppIcon() {
                    Image(nsImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .cornerRadius(18)
                        .shadow(color: .purple.opacity(0.45), radius: 12, x: 0, y: 5)
                } else {
                    Image(systemName: "macwindow.and.cursorarrow")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                }

                Text("DroidMirror Mac")
                    .font(.system(size: 24, weight: .bold))

                Text("Apple Silicon Hardware-Accelerated Android Remote Control")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 3 Methods Cards
            HStack(spacing: 14) {
                methodCard(
                    mode: .usb,
                    title: "1. Wired USB",
                    description: "Connect via USB-C cable for 16 Mbps uncompressed stream with lowest possible latency.",
                    tag: "Fastest"
                )

                methodCard(
                    mode: .homeWiFi,
                    title: "2. Home Wi-Fi",
                    description: "Connect via your local router. Tap 'Prep for Wireless' over USB first or use Android 11+ pairing.",
                    tag: "Convenient"
                )

                methodCard(
                    mode: .phoneHotspot,
                    title: "3. Phone Hotspot",
                    description: "Turn on phone's hotspot, join Mac to it, and connect to gateway IP (e.g. 192.168.43.1).",
                    tag: "Field Work"
                )
            }
            .padding(.horizontal, 24)

            // Multi-Device Detected Pill
            if transport.allDetectedDevices.count > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .foregroundColor(.green)
                    Text("\(transport.allDetectedDevices.count) Phones Detected")
                        .fontWeight(.semibold)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Select target in top bar")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12))
                .cornerRadius(8)
            }

            // Connection Action or Pre-Flight Spinner
            if transport.isPreflighting || transport.isConnecting {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(transport.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
            } else {
                Button(action: {
                    Task { await transport.applySelectedMode() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: transport.selectedMode.iconName)
                        Text("Connect using \(transport.selectedMode.shortTitle)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 10)

                Button(action: {
                    transport.showHelpModal = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "book.pages")
                        Text("Open Connection & Universal Phone Guide (⌘?)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(32)
    }

    private func methodCard(mode: ConnectionMode, title: String, description: String, tag: String) -> some View {
        Button(action: {
            transport.selectMode(mode)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(transport.selectedMode == mode ? .accentColor : .secondary)
                    Spacer()
                    Text(tag)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: 175, height: 160)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(transport.selectedMode == mode ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(transport.selectedMode == mode ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Strip

    private var footerStatusStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(transport.statusMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Text("scrcpy-server v5.0.1 • VideoToolbox H.264 AVCC • TCP_NODELAY")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ??
                     Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                     Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}
