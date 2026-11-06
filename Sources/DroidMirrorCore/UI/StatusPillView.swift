import SwiftUI

public struct StatusPillView: View {
    @ObservedObject var transport: TransportManager

    public init(transport: TransportManager) {
        self.transport = transport
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Status Dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 3)

            // Active Mode / Target
            HStack(spacing: 6) {
                if let mode = transport.activeMode {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text(mode.shortTitle)
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Text("Ready")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                if let target = transport.activeTargetSerial {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(target)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .frame(height: 12)

            // Live FPS & Resolution
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Text("\(transport.fps)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(transport.fps > 0 ? .green : .secondary)
                    Text("FPS")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if transport.resolution.width > 0 && transport.resolution.height > 0 {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(transport.resolution.width)×\(transport.resolution.height)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var statusColor: Color {
        if transport.isPreflighting || transport.isConnecting {
            return .orange
        }
        if transport.isConnected {
            return .green
        }
        return .gray
    }
}
