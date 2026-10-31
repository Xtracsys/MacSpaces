import SwiftUI
import MacSpacesCore

struct OllamaView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedOrphanIDs: Set<BlobInfo.ID> = []
    @State private var modelPendingDelete: OllamaModelInfo?
    @State private var confirmCleanOrphans = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                if let audit = model.ollamaAudit {
                    if !audit.warnings.isEmpty {
                        warningsSection(audit)
                    }
                    orphanSection(audit)
                    modelsSection(audit)
                    if !audit.versionGroups.isEmpty {
                        versionGroupsSection(audit)
                    }
                    footprintSection(audit)
                } else {
                    placeholder
                }
            }
            .padding(20)
        }
        .navigationTitle("Ollama")
        .task {
            if model.ollamaAudit == nil {
                model.runOllamaAudit()
            }
        }
        .confirmationDialog(
            "Clean \(selectedOrphanCount > 0 ? "\(selectedOrphanCount) selected" : "all \(model.ollamaAudit?.orphanedBlobs.count ?? 0)") orphaned blobs?",
            isPresented: $confirmCleanOrphans,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let urls: [URL]?
                if selectedOrphanCount > 0, let audit = model.ollamaAudit {
                    urls = audit.orphanedBlobs.filter { selectedOrphanIDs.contains($0.id) }.map { $0.url }
                } else {
                    urls = nil // all orphans
                }
                model.cleanOrphanedBlobs(urls: urls)
                selectedOrphanIDs.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orphaned blobs are not referenced by any model manifest and are safe to remove. Each blob is re-verified against a fresh audit at deletion time, so blobs claimed by a new pull in the meantime are skipped. They will be moved to the Trash.")
        }
        .confirmationDialog(
            modelPendingDelete.map { "Delete model “\($0.qualifiedName)”?" } ?? "",
            isPresented: Binding(
                get: { modelPendingDelete != nil },
                set: { if !$0 { modelPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Model (manifest + unique blobs)", role: .destructive) {
                if let modelInfo = modelPendingDelete {
                    model.deleteOllamaModel(modelInfo)
                }
                modelPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { modelPendingDelete = nil }
        } message: {
            if let m = modelPendingDelete {
                Text("Blobs shared with other models are kept. The manifest and this model's unique blobs (\(Format.bytes(m.uniqueSize))) will be moved to the Trash.")
            }
        }
    }

    private var selectedOrphanCount: Int { selectedOrphanIDs.count }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            if let audit = model.ollamaAudit {
                StatCard(
                    title: "Models",
                    value: "\(audit.models.count)",
                    detail: Format.bytes(audit.modelsBytes) + " across manifests",
                    systemImage: "square.stack.3d.up",
                    color: .purple
                )
                StatCard(
                    title: "Orphaned Blobs",
                    value: audit.orphanedBlobs.isEmpty ? "None" : "\(audit.orphanedBlobs.count)",
                    detail: audit.orphanedBlobs.isEmpty ? "Every blob is referenced by a model" : Format.bytes(audit.orphanedBytes) + " reclaimable",
                    systemImage: "questionmark.folder",
                    color: audit.orphanedBlobs.isEmpty ? .green : .orange
                )
                StatCard(
                    title: "Ollama Home",
                    value: Format.bytes(audit.modelsRootSize),
                    detail: audit.ollamaHome?.path ?? "",
                    systemImage: "pawprint",
                    color: .indigo
                )
                StatCard(
                    title: "Server",
                    value: audit.ollamaRunning ? "Running" : "Stopped",
                    detail: audit.ollamaRunning ? "Blob deletions take effect after restart" : "No server process detected",
                    systemImage: audit.ollamaRunning ? "bolt.fill" : "moon.zzz",
                    color: audit.ollamaRunning ? .green : .gray
                )
            } else {
                ProgressView("Auditing Ollama…")
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
        }
    }

    private func warningsSection(_ audit: OllamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(audit.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Orphans

    private func orphanSection(_ audit: OllamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Orphaned Blobs",
                subtitle: "Files in blobs/ that no manifest references — re-verified at deletion time"
            ) {
                AnyView(
                    HStack(spacing: 8) {
                        if selectedOrphanCount > 0 {
                            Button("Clear Selection") { selectedOrphanIDs.removeAll() }
                                .buttonStyle(.link)
                        }
                        Button("Clean Orphans…") {
                            confirmCleanOrphans = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(audit.orphanedBlobs.isEmpty)
                    }
                )
            }

            if audit.orphanedBlobs.isEmpty {
                Label("No orphaned blobs — nice and tidy.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(audit.orphanedBlobs) { blob in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { selectedOrphanIDs.contains(blob.id) },
                            set: { on in
                                if on { selectedOrphanIDs.insert(blob.id) } else { selectedOrphanIDs.remove(blob.id) }
                            }
                        )) {
                            Text(blob.fileName)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Text(Format.bytes(blob.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            TrashService.revealInFinder([blob.url])
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Text("\(selectedOrphanCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total reclaimable: \(Format.bytes(audit.orphanedBytes))")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Models

    private func modelsSection(_ audit: OllamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Models",
                subtitle: "\(audit.models.count) manifests"
            ) {
                AnyView(
                    Button {
                        model.runOllamaAudit()
                    } label: {
                        if model.isAuditingOllama {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isAuditingOllama)
                    .help("Re-run audit")
                )
            }
            ForEach(audit.models) { modelInfo in
                HStack(spacing: 10) {
                    Image(systemName: "cube")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelInfo.qualifiedName)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            if OllamaAuditor.looksLikeQuantTag(modelInfo.tag) {
                                StatusBadge(text: "quant", color: .purple)
                            }
                            if modelInfo.sharedLayerCount > 0 {
                                StatusBadge(text: "\(modelInfo.sharedLayerCount) shared", color: .blue)
                            }
                            if !modelInfo.missingBlobDigests.isEmpty {
                                StatusBadge(text: "\(modelInfo.missingBlobDigests.count) missing blobs", color: .red)
                            }
                            Text("\(modelInfo.layerCount) layers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.bytes(modelInfo.totalSize))
                            .monospacedDigit()
                            .font(.callout.weight(.medium))
                        if modelInfo.uniqueSize != modelInfo.totalSize {
                            Text("unique: \(Format.bytes(modelInfo.uniqueSize))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        TrashService.revealInFinder([modelInfo.manifestURL])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal manifest in Finder")
                    Button(role: .destructive) {
                        modelPendingDelete = modelInfo
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete model")
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Version groups (feature: model version manager)

    private func versionGroupsSection(_ audit: OllamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Version Groups",
                subtitle: "Base models pulled with multiple tags — consider retiring old quants"
            )

            ForEach(audit.versionGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.purple)
                        Text(group.baseName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(group.totalSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(group.variants.enumerated()), id: \.element.id) { index, variant in
                        HStack(spacing: 8) {
                            Image(systemName: index == 0 ? "star.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(index == 0 ? .yellow : .secondary)
                                .help(index == 0 ? "Newest manifest" : "Older variant")
                            Text(variant.tag)
                                .font(.system(.callout, design: .monospaced))
                            if OllamaAuditor.looksLikeQuantTag(variant.tag) {
                                StatusBadge(text: "quant", color: .purple)
                            }
                            Spacer()
                            Text(Format.bytes(variant.totalSize))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                modelPendingDelete = variant
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this variant")
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Footprint

    private func footprintSection(_ audit: OllamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "~/.ollama Footprint",
                subtitle: audit.ollamaHome?.path ?? ""
            )
            ForEach(audit.footprint) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.name == "models" ? "shippingbox" : "folder")
                        .foregroundStyle(.secondary)
                    Text(item.name)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning Ollama manifests and blobs…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
