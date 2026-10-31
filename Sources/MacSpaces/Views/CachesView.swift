import SwiftUI
import MacSpacesCore

struct CachesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCacheIDs: Set<CacheItem.ID> = []
    @State private var confirmCleanCaches = false
    @State private var confirmThinSnapshots = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                if let audit = model.cachesAudit {
                    cachesSection(audit)
                } else {
                    placeholder("Scanning developer caches…")
                }
                snapshotsSection
            }
            .padding(20)
        }
        .navigationTitle("Caches & Snapshots")
        .task {
            if model.cachesAudit == nil {
                model.runCachesAudit()
            }
            if model.snapshots.isEmpty && !model.isAuditingSnapshots {
                model.runSnapshotAudit()
            }
        }
        .confirmationDialog(
            "Clean \(selectedCacheIDs.isEmpty ? "all" : "\(selectedCacheIDs.count)") cache item(s)?",
            isPresented: $confirmCleanCaches,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let items = (model.cachesAudit?.items ?? []).filter { selectedCacheIDs.contains($0.id) }
                let chosen = selectedCacheIDs.isEmpty ? (model.cachesAudit?.items ?? []) : items
                model.cleanCacheItems(chosen)
                selectedCacheIDs.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cache directories are rebuilt automatically by Xcode and SwiftPM. Everything will be moved to the Trash. Total: \(Format.bytes(selectedBytes)).")
        }
        .confirmationDialog(
            "Thin local Time Machine snapshots?",
            isPresented: $confirmThinSnapshots,
            titleVisibility: .visible
        ) {
            Button("Thin Snapshots", role: .destructive) {
                model.thinSnapshots()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS will delete the oldest local snapshots until up to 20 GB of space is freed. This does not affect backups on your Time Machine drive.")
        }
    }

    private var selectedBytes: Int64 {
        (model.cachesAudit?.items ?? [])
            .filter { selectedCacheIDs.isEmpty || selectedCacheIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Developer Caches",
                value: model.cachesAudit.map { Format.bytes($0.totalBytes) } ?? "…",
                detail: "\(model.cachesAudit?.items.count ?? 0) items — rebuilt automatically on demand",
                systemImage: "wrench.and.screwdriver",
                color: .pink
            )
            StatCard(
                title: "Local Snapshots",
                value: "\(model.snapshots.count)",
                detail: model.snapshots.isEmpty
                    ? "None (or Time Machine local snapshots are disabled)"
                    : "APFS local snapshots — purgeable, but they hold space until thinned",
                systemImage: "clock.arrow.circlepath",
                color: .indigo
            )
        }
    }

    // MARK: - Caches

    private func cachesSection(_ audit: CachesAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Developer Caches",
                subtitle: "DerivedData, Archives, Device Support, Simulator caches, SwiftPM"
            ) {
                AnyView(
                    HStack(spacing: 8) {
                        Button {
                            model.runCachesAudit()
                        } label: {
                            if model.isAuditingCaches {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isAuditingCaches)
                        .help("Re-run audit")

                        Button("Clean…") { confirmCleanCaches = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(audit.items.isEmpty)
                    }
                )
            }

            ForEach(audit.items) { item in
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { selectedCacheIDs.contains(item.id) },
                        set: { on in
                            if on { selectedCacheIDs.insert(item.id) } else { selectedCacheIDs.remove(item.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                StatusBadge(text: item.category.rawValue, color: .pink)
                            }
                            Text(Format.tildify(item.path))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(Format.bytes(item.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        TrashService.revealInFinder([item.url])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
            }

            if audit.items.isEmpty {
                Label("No developer caches found — nothing to reclaim.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Snapshots

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Local Time Machine Snapshots",
                subtitle: "APFS snapshots kept on the startup disk between backups"
            ) {
                AnyView(
                    HStack(spacing: 8) {
                        Button {
                            model.runSnapshotAudit()
                        } label: {
                            if model.isAuditingSnapshots {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isAuditingSnapshots)
                        .help("Re-run audit")

                        Button("Thin Snapshots…") { confirmThinSnapshots = true }
                            .buttonStyle(.bordered)
                            .disabled(model.snapshots.isEmpty)
                    }
                )
            }

            if !model.snapshotWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.snapshotWarnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if model.snapshots.isEmpty {
                Label("No local snapshots. macOS purges these automatically when space is needed.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(model.snapshots) { snapshot in
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.indigo)
                        Text(snapshot.name)
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        if let date = snapshot.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if let result = model.lastThinResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
