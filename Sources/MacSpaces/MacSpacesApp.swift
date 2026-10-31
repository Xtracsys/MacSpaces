import SwiftUI
import AppKit
import MacSpacesCore

@main
struct MacSpacesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        // CLI companion modes (report export / launchd digest) never show UI.
        if ScheduledAudit.handleLaunchArguments() {
            exit(0)
        }
        _model = StateObject(wrappedValue: AppModel())
    }

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
                .frame(width: 560, height: 560)
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
        for name in ["showSettingsWindow:", "showSettings:", "showPreferencesWindow:"] {
            let action = Selector(name)
            if NSApp.responds(to: action) {
                NSApp.sendAction(action, to: nil, from: nil)
                return
            }
        }
    }

    var body: some View {
        Section("Volumes") {
            ForEach(model.volumeMonitor.volumes) { volume in
                Text("\(volume.name): \(Format.bytes(volume.availableCapacity)) free of \(Format.bytes(volume.totalCapacity))")
            }
        }
        Divider()
        // Quick-clean actions (work once the audits have data).
        Section("Quick clean") {
            let orphanCount = model.ollamaAudit?.orphanedBlobs.count ?? 0
            let orphanBytes = model.ollamaAudit?.orphanedBytes ?? 0
            Button(orphanCount > 0
                   ? "Trash \(orphanCount) orphaned Ollama blobs (\(Format.bytes(orphanBytes)))"
                   : "No orphaned Ollama blobs") {
                model.cleanOrphanedBlobs()
            }
            .disabled(orphanCount == 0)

            let dupeCount = model.llamaAudit?.duplicateGroups.count ?? 0
            let dupeBytes = model.llamaAudit?.duplicateReclaimableBytes ?? 0
            Button(dupeCount > 0
                   ? "Trash duplicate GGUFs (\(Format.bytes(dupeBytes)))"
                   : "No duplicate GGUFs") {
                guard let groups = model.llamaAudit?.duplicateGroups, !groups.isEmpty else { return }
                let files = groups.flatMap { $0.dropFirst() }
                model.deleteFiles(at: files.map { URL(fileURLWithPath: $0.path) }, mode: .trash, refresh: [.llama])
            }
            .disabled(dupeCount == 0)

            if model.ollamaAudit == nil || model.llamaAudit == nil {
                Button("Run audits") {
                    model.runOllamaAudit()
                    model.runLlamaAudit()
                }
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
