import SwiftUI

public final class PairingViewModel: ObservableObject {
    @Published public var pairIP: String = ""
    @Published public var pairPort: String = ""
    @Published public var pairCode: String = ""
    @Published public var isPairing: Bool = false
    @Published public var pairingResult: String?
    @Published public var errorMessage: String?

    public init() {}
}

public struct WirelessPairingModal: View {
    @ObservedObject var transport: TransportManager
    @StateObject private var vm = PairingViewModel()
    @Environment(\.dismiss) private var dismiss

    public init(transport: TransportManager) {
        self.transport = transport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                Text("Android 11+ Wireless Debugging Pairing")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("On your phone, enable Developer Options → Wireless debugging → tap 'Pair device with pairing code'. Enter the shown IP, Port, and 6-digit code below.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Form
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phone IP Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. 192.168.1.45", text: $vm.pairIP)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pairing Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. 41235", text: $vm.pairPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("6-Digit Pairing Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. 492817", text: $vm.pairCode)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let result = vm.pairingResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if let error = vm.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: { executePairing() }) {
                    if vm.isPairing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Pair Device")
                            .padding(.horizontal, 8)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isPairing || vm.pairIP.isEmpty || vm.pairPort.isEmpty || vm.pairCode.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if !transport.wifiInputIP.isEmpty {
                vm.pairIP = transport.wifiInputIP
            }
        }
    }

    private func executePairing() {
        vm.errorMessage = nil
        vm.pairingResult = nil
        vm.isPairing = true

        guard let portInt = Int(vm.pairPort.trimmingCharacters(in: .whitespaces)) else {
            vm.errorMessage = "Port must be a valid number"
            vm.isPairing = false
            return
        }

        let cleanIP = vm.pairIP.trimmingCharacters(in: .whitespaces)
        let cleanCode = vm.pairCode.trimmingCharacters(in: .whitespaces)

        Task {
            let res = await transport.adb.pairDevice(ip: cleanIP, port: portInt, code: cleanCode)
            vm.isPairing = false
            switch res {
            case .success:
                vm.pairingResult = "Successfully paired! You can now connect."
                transport.wifiInputIP = cleanIP
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            case .failure(let err):
                vm.errorMessage = err.localizedDescription
            }
        }
    }
}
