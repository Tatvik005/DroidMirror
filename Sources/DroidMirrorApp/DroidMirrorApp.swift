import SwiftUI
import AppKit
import DroidMirrorCore

@main
struct DroidMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 960, height: 820)
        .commands {
            CommandMenu("Device") {
                Button("Wired USB Mode") {
                    TransportManager.shared.selectMode(.usb)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Home Wi-Fi Mode") {
                    TransportManager.shared.selectMode(.homeWiFi)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Phone Hotspot Mode") {
                    TransportManager.shared.selectMode(.phoneHotspot)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Connect / Apply Mode") {
                    Task {
                        await TransportManager.shared.applySelectedMode()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Disconnect") {
                    TransportManager.shared.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Floating Phone Window") {
                    TransportManager.shared.toggleFloatingWindow()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("Control") {
                Button("Power") {
                    TransportManager.shared.togglePower()
                }
                .keyboardShortcut("p", modifiers: [.command, .control])

                Button("Home") {
                    TransportManager.shared.home()
                }
                .keyboardShortcut("h", modifiers: [.command, .control])

                Button("Back") {
                    TransportManager.shared.back()
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("App Switcher") {
                    TransportManager.shared.appSwitcher()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()

                Button("Volume Up") {
                    TransportManager.shared.volumeUp()
                }
                .keyboardShortcut("=", modifiers: [.command, .control])

                Button("Volume Down") {
                    TransportManager.shared.volumeDown()
                }
                .keyboardShortcut("-", modifiers: [.command, .control])

                Divider()

                Button("Toggle Screen-Off Mirroring") {
                    TransportManager.shared.toggleScreenOffMirroring()
                }
                .keyboardShortcut("o", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .help) {
                Button("DroidMirror Help & Switch Guide") {
                    TransportManager.shared.showHelpModal = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Set custom app icon directly on NSApp so Dock icon updates immediately
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ??
                         Bundle.main.url(forResource: "AppIcon", withExtension: "png") ??
                         Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TransportManager.shared.disconnect()
    }
}
