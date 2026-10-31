import MacSpacesCore
import SwiftUI

struct DiskTreeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [DiskNode] = []
    @State private var displayMode: DisplayMode = .spaceMap
    @State private var nodePendingDelete: DiskNode?
    @State private var scanTargetConfirmation: ScanTarget?

    enum DisplayMode: String, CaseIterable, Identifiable {
        case spaceMap = "Space Map"
        case directory = "Directory"
        case largest = "Largest Files"
        var id: String { rawValue }
    }

    enum ScanTarget: String, Identifiable {
        case home, fileSystemRoot
        var id: String { rawValue }
        var url: URL {
            switch self {
            case .home: return FileManager.default.homeDirectoryForCurrentUser
            case .fileSystemRoot: return URL(fileURLWithPath: "/")
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.isScanning {
                    scanningView
                } else if let root = model.diskRoot {
                    switch displayMode {
                    case .spaceMap: spaceMapView(root: root)
                    case .directory: treeList(root: root)
                    case .largest: largestFilesList(root: root)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle(currentTitle)
            .navigationDestination(for: DiskNode.self) { node in
                treeList(root: node)
            }
        }
        .toolbar {
            // The mode switch is the primary control: centered in the
            // toolbar (principal placement) with short labels so it uses the
            // top bar without truncating.
            ToolbarItem(placement: .principal) {
                Picker("", selection: $displayMode) {
                    Text("Map").tag(DisplayMode.spaceMap)
                    Text("Tree").tag(DisplayMode.directory)
                    Text("Files").tag(DisplayMode.largest)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .help("Disk usage view mode")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Scan Home Folder") { model.scanDisk(root: ScanTarget.home.url) }
                    Button("Scan Entire Startup Disk…") { scanTargetConfirmation = .fileSystemRoot }
                    Divider()
                    Section("Mounted Drives") {
                        ForEach(model.volumeMonitor.volumes) { volume in
                            Button {
                                path.removeAll()
                                model.scanDisk(root: volume.url)
                            } label: {
                                Label(volume.name, systemImage: volume.url.path == "/" ? "internaldrive" : "externaldrive")
                            }
                        }
                    }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Rescan disk usage")

                if model.isScanning {
                    Button {
                        model.cancelScan()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Scan the entire startup disk?",
            isPresented: Binding(get: { scanTargetConfirmation != nil }, set: { if !$0 { scanTargetConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Scan Entire Disk") {
                if let target = scanTargetConfirmation {
                    model.scanDisk(root: target.url)
                }
            }
            Button("Cancel", role: .cancel) { scanTargetConfirmation = nil }
        } message: {
            Text("A full scan can take several minutes and may skip system-protected folders without Full Disk Access.")
        }
        .onDeleteConfirmation(target: $nodePendingDelete, model: model)
    }

    private var currentTitle: String {
        if model.isScanning { return "Scanning…" }
        return path.last?.name ?? model.diskRoot?.name ?? "Disk Usage"
    }

    // MARK: - States

    private var scanningView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning \(model.scanRootPath)")
                .font(.headline)
            Text(model.scanProgress.currentItem)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            Text("\(model.scanProgress.scannedItems) items · \(Format.bytes(model.scanProgress.scannedBytes)) seen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No scan yet")
                .font(.title3.weight(.semibold))
            Text("Scan your home folder or the entire disk to see what is using space.")
                .foregroundStyle(.secondary)
            Button("Scan Home Folder") {
                model.scanDisk(root: ScanTarget.home.url)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Space map

    private func spaceMapView(root: DiskNode) -> some View {
        SpaceMapView(rootNode: root)
            .padding(12)
    }

    // MARK: - Tree

    private func treeList(root: DiskNode) -> some View {
        List {
            if root.path != (model.diskRoot?.path ?? "") {
                Section {
                    Button {
                        if !path.isEmpty { path.removeLast() }
                    } label: {
                        Label("Back to \(path.dropLast().last?.name ?? model.diskRoot?.name ?? "root")", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section {
                summaryRow(root: root)
            }
            Section("Contents") {
                ForEach(root.children) { child in
                    childRow(child)
                }
                if root.children.isEmpty {
                    Text(root.accessDenied ? "No access to this folder." : "No items.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    private func summaryRow(root: DiskNode) -> some View {
        HStack {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(root.path)
                    .font(.caption)
                    .textSelection(.enabled)
                Text("\(Format.bytes(root.totalBytes)) · \(root.itemCount) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func childRow(_ child: DiskNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(child.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            if child.isDirectory {
                NavigationLink(value: child) {
                    nodeText(child)
                }
                .buttonStyle(.borderless)
            } else {
                nodeText(child)
            }
            Spacer()
            Text(Format.bytes(child.totalBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") { TrashService.revealInFinder([child.url]) }
            Divider()
            Button("Move to Trash…", role: .destructive) { nodePendingDelete = child }
        }
    }

    private func nodeText(_ node: DiskNode) -> some View {
        HStack(spacing: 6) {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.accessDenied {
                Image(systemName: "lock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("No access — size may be incomplete")
            }
        }
    }

    // MARK: - Largest files

    private func largestFilesList(root: DiskNode) -> some View {
        let files = root.largestFiles(limit: 150)
        let maxSize = files.first?.totalBytes ?? 1
        return List {
            Section {
                ForEach(files) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        SizeBar(fraction: Double(file.totalBytes) / Double(maxSize))
                            .frame(width: 90)
                        Text(Format.bytes(file.totalBytes))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Reveal in Finder") { TrashService.revealInFinder([file.url]) }
                        Divider()
                        Button("Move to Trash…", role: .destructive) { nodePendingDelete = file }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - Shared delete confirmation

private struct DeleteConfirmationModifier: ViewModifier {
    @Binding var target: DiskNode?
    let model: AppModel
    @State private var mode: DeletionMode = .trash

    func body(content: Content) -> some View {
        content.confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { target != nil },
                set: { if !$0 { target = nil } }
            ),
            titleVisibility: .visible
        ) {
            if model.deleteMode == .trash {
                Button("Move to Trash", role: .destructive) {
                    if let node = target { model.deleteDiskNode(node, mode: .trash) }
                    target = nil
                }
            } else {
                Button("Delete Permanently", role: .destructive) {
                    if let node = target { model.deleteDiskNode(node, mode: .permanent) }
                    target = nil
                }
                Button("Move to Trash Instead") {
                    if let node = target { model.deleteDiskNode(node, mode: .trash) }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: {
            if let node = target {
                Text("\(node.name) (\(Format.bytes(node.totalBytes))) will be \(model.deleteMode == .trash ? "moved to the Trash" : "permanently deleted"). This cannot be undone.")
            }
        }
    }

    private var deleteTitle: String {
        target.map { "Delete “\($0.name)”?" } ?? "Delete?"
    }
}

extension View {
    func onDeleteConfirmation(target: Binding<DiskNode?>, model: AppModel) -> some View {
        modifier(DeleteConfirmationModifier(target: target, model: model))
    }
}
