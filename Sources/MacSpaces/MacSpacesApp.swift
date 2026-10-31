import MacSpacesCore
import SwiftUI
import AppKit

@main
struct MacSpacesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacSpaces") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 520, height: 420)
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            VolumeMenuBarLabel(monitor: model.volumeMonitor)
        }
    }
}

/// Keeps the Dock icon and activates the app when launched via `open`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Menu bar extra

private struct VolumeMenuBarLabel: View {
    @ObservedObject var monitor: VolumeMonitor

    var body: some View {
        if let volume = monitor.primaryVolume {
            Text("\(Int((1 - volume.usedFraction) * 100))% free · \(Format.bytes(volume.availableCapacity))")
        } else {
            Text("MacSpaces")
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    /// Opens the Settings scene on macOS 13–26 via the responder chain.
    private func openSettings() {
        let selectors = ["showSettingsWindow:", "showSettings:"]
        for name in selectors {
            let action = Selector(name)
            if NSApp.responds(to: action) {
                NSApp.sendAction(action, to: nil, from: nil)
                return
            }
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    var body: some View {
        Section("Volumes") {
            ForEach(model.volumeMonitor.volumes) { volume in
                Text("\(volume.name): \(Format.bytes(volume.availableCapacity)) free of \(Format.bytes(volume.totalCapacity))")
            }
        }
        Divider()
        Button("Open MacSpaces") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        Button("Settings…") {
            openSettings()
        }
        Divider()
        Button("Quit MacSpaces") { NSApp.terminate(nil) }
    }
}
