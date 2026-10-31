import MacSpacesCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case disk
    case ollama
    case llama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .disk: return "Disk Usage"
        case .ollama: return "Ollama"
        case .llama: return "llama.cpp"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.needle"
        case .disk: return "internaldrive"
        case .ollama: return "pawprint"
        case .llama: return "cpu"
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
                            .badge(badgeCount(for: item))
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

    /// Little badges on the sidebar entries (orphan count, duplicate groups, etc.).
    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .ollama:
            return model.ollamaAudit?.orphanedBlobs.count ?? 0
        case .llama:
            return model.llamaAudit?.duplicateGroups.count ?? 0
        default:
            return 0
        }
    }
}
