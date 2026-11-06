import SwiftUI

public struct FloatingToolbarView: View {
    @ObservedObject var transport: TransportManager

    public init(transport: TransportManager) {
        self.transport = transport
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Power
            ToolbarButton(
                icon: "power",
                tooltip: "Power Button",
                action: { transport.togglePower() }
            )

            // Volume Up
            ToolbarButton(
                icon: "speaker.plus",
                tooltip: "Volume Up",
                action: { transport.volumeUp() }
            )

            // Volume Down
            ToolbarButton(
                icon: "speaker.minus",
                tooltip: "Volume Down",
                action: { transport.volumeDown() }
            )

            Divider()
                .frame(width: 20)

            // Back
            ToolbarButton(
                icon: "chevron.backward",
                tooltip: "Back (or Right-Click)",
                action: { transport.back() }
            )

            // Home
            ToolbarButton(
                icon: "circle.circle",
                tooltip: "Home (or Middle-Click)",
                action: { transport.home() }
            )

            // App Switcher
            ToolbarButton(
                icon: "square.stack.3d.down.right",
                tooltip: "Recent Apps / Overview",
                action: { transport.appSwitcher() }
            )

            Divider()
                .frame(width: 20)

            // Notifications
            ToolbarButton(
                icon: "bell",
                tooltip: "Notification Shade",
                action: { ControlInjector.shared.expandNotificationPanel() }
            )

            // Screen-Off Mirroring
            ToolbarButton(
                icon: transport.isScreenOff ? "display.slash.fill" : "display",
                tooltip: transport.isScreenOff ? "Turn Phone Screen ON" : "Turn Phone Screen OFF (Save Battery)",
                activeColor: transport.isScreenOff ? .purple : .primary,
                action: { transport.toggleScreenOffMirroring() }
            )

            if transport.isConnected {
                Divider()
                    .frame(width: 20)

                // Compact Floating Window
                ToolbarButton(
                    icon: transport.isFloatingWindow ? "arrow.up.left.and.arrow.down.right" : "pip.enter",
                    tooltip: transport.isFloatingWindow ? "Exit Floating Window" : "Compact Floating Phone Window (⇧⌘F)",
                    activeColor: .purple,
                    action: { transport.toggleFloatingWindow() }
                )

                // Disconnect
                ToolbarButton(
                    icon: "xmark.circle",
                    tooltip: "Disconnect Stream",
                    activeColor: .red,
                    action: { transport.disconnect() }
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    var activeColor: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(activeColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(tooltip)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.15) : Color.clear)
            )
    }
}
