import MacSpacesCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("deleteMode") private var deleteModeRaw: String = DeletionMode.trash.rawValue

    @State private var ggufFolders: [String] = []
    @State private var sourceRoots: [String] = []
    @State private var showingFolderPicker = false
    @State private var newRootPath = ""

    var body: some View {
        Form {
            Section("Deletion") {
                Picker("Default delete behavior:", selection: $deleteModeRaw) {
                    Text("Move to Trash (recommended)").tag(DeletionMode.trash.rawValue)
                    Text("Delete permanently").tag(DeletionMode.permanent.rawValue)
                }
                .pickerStyle(.radioGroup)
                Text("Every delete action always asks for confirmation first.")
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
                        Text(expandForDisplay(folder))
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

            Section("About") {
                LabeledContent("MacSpaces", value: "1.0")
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
                // Store as ~-relative when inside the home directory for portability.
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let path = url.path.hasPrefix(home)
                    ? "~" + url.path.dropFirst(home.count)
                    : url.path
                if !ggufFolders.contains(path) {
                    ggufFolders.append(path)
                    saveGGUFFolders()
                }
            }
        }
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

    private func expandForDisplay(_ path: String) -> String {
        path // already stored in ~ form when possible
    }

    private func load() {
        let rawFolders = UserDefaults.standard.string(forKey: "customGGUFFolders") ?? ""
        let storedFolders = rawFolders.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        ggufFolders = storedFolders.isEmpty ? LlamaAuditor.defaultCustomFolders : storedFolders

        let rawRoots = UserDefaults.standard.string(forKey: "sourceScanRoots") ?? ""
        let storedRoots = rawRoots.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        sourceRoots = storedRoots.isEmpty ? LlamaAuditor.defaultSourceRoots : storedRoots
    }

    private func saveGGUFFolders() {
        UserDefaults.standard.set(ggufFolders.joined(separator: "\n"), forKey: "customGGUFFolders")
    }

    private func saveSourceRoots() {
        UserDefaults.standard.set(sourceRoots.joined(separator: "\n"), forKey: "sourceScanRoots")
    }
}
