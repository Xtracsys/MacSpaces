import SwiftUI
import UniformTypeIdentifiers
import MacSpacesCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("deleteMode") private var deleteModeRaw: String = DeletionMode.trash.rawValue

    @State private var ggufFolders: [String] = []
    @State private var sourceRoots: [String] = []
    @State private var showingFolderPicker = false
    @State private var newRootPath = ""

    // Ignore rules (feature 8)
    @State private var ignoreText: String = ""

    // Folder watcher (feature 5)
    @State private var watchFolders: [String] = []
    @State private var watchThresholdGB: Double = 10
    @State private var showingWatchFolderPicker = false

    // Scheduled audit (feature 6)
    @State private var weeklyAuditEnabled = false

    var body: some View {
        Form {
            Section("Deletion") {
                Picker("Default delete behavior:", selection: $deleteModeRaw) {
                    Text("Move to Trash (recommended)").tag(DeletionMode.trash.rawValue)
                    Text("Delete permanently").tag(DeletionMode.permanent.rawValue)
                }
                .pickerStyle(.radioGroup)
                Text("Every delete action always asks for confirmation first. Ollama orphan cleanup is always Trash-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom GGUF Folders") {
                Text("Folders scanned recursively for loose .gguf model files (deduped by content fingerprint).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ggufFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            ggufFolders.removeAll { $0 == folder }
                            saveGGUFFolders()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove folder")
                    }
                }
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Add Folder…", systemImage: "plus.circle")
                }
                Button("Restore Default (~/.ollama/models/ggufs)") {
                    ggufFolders = LlamaAuditor.defaultCustomFolders
                    saveGGUFFolders()
                }
            }

            Section("Source Scan Roots") {
                Text("Folders searched (3 levels deep) for llama.cpp source checkouts and local builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sourceRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text(root)
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            sourceRoots.removeAll { $0 == root }
                            saveSourceRoots()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove root")
                    }
                }
                HStack {
                    TextField("~/path/to/folder", text: $newRootPath)
                        .onSubmit(addSourceRoot)
                    Button("Add") { addSourceRoot() }
                        .disabled(newRootPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore Defaults") {
                    sourceRoots = LlamaAuditor.defaultSourceRoots
                    saveSourceRoots()
                }
            }

            Section("Ignore Rules") {
                Text("Glob patterns — one per line. * matches within a path segment, ** matches across segments, a trailing / excludes a directory anywhere. Applies to disk scans and GGUF collection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $ignoreText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 90)
                    .border(Color.secondary.opacity(0.2))
                HStack {
                    Button("Save Patterns") {
                        IgnoreRules.shared.setPatterns(ignoreText.split(separator: "\n").map(String.init))
                        UserDefaults.standard.set(ignoreText, forKey: IgnoreRules.defaultsKey)
                    }
                    .disabled(ignoreText == (UserDefaults.standard.string(forKey: IgnoreRules.defaultsKey) ?? ""))
                    Button("Clear All") { ignoreText = "" }
                }
                Text("Examples: node_modules/ · *.tmp · ~/Library/Caches/**")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Folder Watcher") {
                Text("Watch folders and surface a Dashboard alert when one grows past the threshold. Checked every 5 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(watchFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "eye")
                        Text(folder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            watchFolders.removeAll { $0 == folder }
                            WatchService.setFolders(watchFolders)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop watching")
                    }
                }
                HStack {
                    Button {
                        showingWatchFolderPicker = true
                    } label: {
                        Label("Watch Folder…", systemImage: "plus.circle")
                    }
                    Spacer()
                    LabeledContent("Threshold (GB)") {
                        TextField("10", value: $watchThresholdGB, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(width: 200)
                    Button("Save") {
                        WatchService.setThresholdGB(watchThresholdGB)
                    }
                }
            }

            Section("Scheduled Audit") {
                Toggle("Weekly digest notification (Fridays 10:00)", isOn: $weeklyAuditEnabled)
                    .onChange(of: weeklyAuditEnabled) { enabled in
                        _ = ScheduledAudit.setLaunchAgent(enabled: enabled)
                        if enabled {
                            // Run one now so the first report exists.
                            Task.detached(priority: .utility) {
                                ScheduledAudit.writeReport(ScheduledAudit.run())
                            }
                        }
                    }
                Text("Runs the app headless (\(ScheduledAudit.launchAgentLabel) launchd agent) and posts a reclaimable-space digest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Report Export") {
                Button {
                    model.exportReport()
                } label: {
                    Label("Export Audit Report (JSON)…", systemImage: "square.and.arrow.up")
                }
                Text("The app binary also doubles as a CLI: `MacSpaces --audit-json` prints a full report to stdout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("MacSpaces", value: "1.1")
                LabeledContent("Tip", value: "Grant Full Disk Access in System Settings for complete scans.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                addFolder(url) { ggufFolders.append($0); saveGGUFFolders() }
            }
        }
        .fileImporter(
            isPresented: $showingWatchFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                addFolder(url) { watchFolders.append($0); WatchService.setFolders(watchFolders) }
            }
        }
    }

    private func addFolder(_ url: URL, then commit: @escaping (String) -> Void) {
        // Store as ~-relative when inside the home directory for portability.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
        commit(path)
    }

    private func addSourceRoot() {
        let trimmed = newRootPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let path = trimmed.hasPrefix("/") || trimmed.hasPrefix("~") ? trimmed : "~/\(trimmed)"
        if !sourceRoots.contains(path) {
            sourceRoots.append(path)
            saveSourceRoots()
        }
        newRootPath = ""
    }

    private func load() {
        let foldersSet = UserDefaults.standard.object(forKey: "customGGUFFolders") != nil
        let rawFolders = UserDefaults.standard.string(forKey: "customGGUFFolders") ?? ""
        let storedFolders = rawFolders.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        ggufFolders = foldersSet ? storedFolders : LlamaAuditor.defaultCustomFolders

        let rootsSet = UserDefaults.standard.object(forKey: "sourceScanRoots") != nil
        let rawRoots = UserDefaults.standard.string(forKey: "sourceScanRoots") ?? ""
        let storedRoots = rawRoots.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        sourceRoots = rootsSet ? storedRoots : LlamaAuditor.defaultSourceRoots

        ignoreText = UserDefaults.standard.string(forKey: IgnoreRules.defaultsKey) ?? ""

        watchFolders = WatchService.configuredFolders().map { Format.tildify($0.path) }
        let gb = UserDefaults.standard.double(forKey: WatchService.thresholdKey)
        watchThresholdGB = gb > 0 ? gb : 10
        weeklyAuditEnabled = ScheduledAudit.isLaunchAgentInstalled
    }

    private func saveGGUFFolders() {
        // Save even when empty — an explicit empty list overrides the default.
        UserDefaults.standard.set(ggufFolders.joined(separator: "\n"), forKey: "customGGUFFolders")
    }

    private func saveSourceRoots() {
        UserDefaults.standard.set(sourceRoots.joined(separator: "\n"), forKey: "sourceScanRoots")
    }
}
