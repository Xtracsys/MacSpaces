import SwiftUI
import MacSpacesCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case disk
    case ollama
    case llama
    case caches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .disk: return "Disk Usage"
        case .ollama: return "Ollama"
        case .llama: return "llama.cpp"
        case .caches: return "Caches & Snapshots"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.needle"
        case .disk: return "internaldrive"
        case .ollama: return "pawprint"
        case .llama: return "cpu"
        case .caches: return "archivebox"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Monitor") {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .badge(badgeCount(for: item).map { Text("\($0)") })
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("MacSpaces")
        } detail: {
            switch selection {
            case .dashboard: DashboardView(selection: $selection)
            case .disk: DiskTreeView()
            case .ollama: OllamaView()
            case .llama: LlamaView()
            case .caches: CachesView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let summary = model.lastDeletionSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
    }

    /// Sidebar badges (orphan count, duplicate groups, reclaimable caches).
    /// Returns nil for zero so no "0" badge renders.
    private func badgeCount(for item: SidebarItem) -> Int? {
        switch item {
        case .ollama:
            let count = model.ollamaAudit?.orphanedBlobs.count ?? 0
            return count > 0 ? count : nil
        case .llama:
            let count = model.llamaAudit?.duplicateGroups.count ?? 0
            return count > 0 ? count : nil
        case .caches:
            guard let audit = model.cachesAudit, audit.totalBytes > 0 else { return nil }
            return nil // caches show their size in the tab itself, not a badge
        default:
            return nil
        }
    }
}
