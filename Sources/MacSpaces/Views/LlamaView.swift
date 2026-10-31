import SwiftUI
import MacSpacesCore

struct LlamaView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dirPendingDelete: ModelDirInfo?
    @State private var duplicatesPendingDelete: [GGUFFile]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                if let audit = model.llamaAudit {
                    if !audit.warnings.isEmpty {
                        warningsSection(audit)
                    }
                    installsSection(audit)
                    duplicatesSection(audit)
                    modelsSection(audit)
                } else {
                    placeholder
                }
            }
            .padding(20)
        }
        .navigationTitle("llama.cpp")
        .task {
            if model.llamaAudit == nil {
                model.runLlamaAudit()
            }
        }
        .confirmationDialog(
            dirPendingDelete.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { dirPendingDelete != nil },
                set: { if !$0 { dirPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete (\(Format.bytes(dirPendingDelete?.totalBytes ?? 0)))", role: .destructive) {
                if let dir = dirPendingDelete {
                    // Force Trash: the dialog advertises Trash semantics.
                    model.deleteFiles(at: [dir.url], mode: .trash, refresh: [.llama])
                }
                dirPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { dirPendingDelete = nil }
        } message: {
            if let dir = dirPendingDelete {
                Text("“\(dir.path)” will be moved to the Trash.")
            }
        }
        .confirmationDialog(
            "Trash duplicate GGUFs?",
            isPresented: Binding(
                get: { duplicatesPendingDelete != nil },
                set: { if !$0 { duplicatesPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Duplicates to Trash", role: .destructive) {
                if let files = duplicatesPendingDelete {
                    model.deleteFiles(at: files.map { URL(fileURLWithPath: $0.path) }, mode: .trash, refresh: [.llama])
                }
                duplicatesPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { duplicatesPendingDelete = nil }
        } message: {
            if let files = duplicatesPendingDelete {
                let bytes = files.reduce(Int64(0)) { $0 + $1.size }
                Text("\(files.count) duplicate files (\(Format.bytes(bytes))) will be moved to the Trash. One copy of each is kept.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            if let audit = model.llamaAudit {
                StatCard(
                    title: "Installs",
                    value: audit.installs.isEmpty ? "None" : "\(audit.installs.count)",
                    detail: audit.installs.isEmpty ? "No llama.cpp binaries found" : Format.bytes(audit.installs.reduce(0) { $0 + $1.totalBytes }) + " on disk",
                    systemImage: "hammer",
                    color: .teal
                )
                StatCard(
                    title: "Models",
                    value: "\(audit.modelDirs.reduce(0) { $0 + $1.ggufFiles.count }) GGUFs",
                    detail: Format.bytes(audit.ggufBytes) + " in \(audit.modelDirs.count) locations",
                    systemImage: "shippingbox",
                    color: .blue
                )
                StatCard(
                    title: "Duplicates",
                    value: audit.duplicateGroups.isEmpty ? "None" : "\(audit.duplicateGroups.count) groups",
                    detail: audit.duplicateGroups.isEmpty ? "All GGUFs are unique" : Format.bytes(audit.duplicateReclaimableBytes) + " reclaimable",
                    systemImage: "doc.on.doc",
                    color: audit.duplicateGroups.isEmpty ? .green : .orange
                )
            } else {
                ProgressView("Auditing llama.cpp…")
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
        }
    }

    private func warningsSection(_ audit: LlamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(audit.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Installs

    private func installsSection(_ audit: LlamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Installations",
                subtitle: "Homebrew packages and source checkouts"
            ) {
                AnyView(
                    Button {
                        model.runLlamaAudit()
                    } label: {
                        if model.isAuditingLlama {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isAuditingLlama)
                    .help("Re-run audit")
                )
            }
            if audit.installs.isEmpty {
                Label("No llama.cpp installs found in Homebrew or scanned source roots.", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(audit.installs) { install in
                    HStack(spacing: 10) {
                        Image(systemName: install.kind == .homebrew ? "drafting.compass" : "hammer.fill")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(install.name).font(.callout.weight(.medium))
                                StatusBadge(text: install.kind.rawValue, color: install.kind == .homebrew ? .orange : .teal)
                                if let version = install.version {
                                    Text(version)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(install.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !install.executables.isEmpty {
                                Text("\(install.executables.count) executables (llama-cli…)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.bytes(install.totalBytes))
                                .monospacedDigit()
                            if install.buildBytes > 0 {
                                Text("build: \(Format.bytes(install.buildBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            TrashService.revealInFinder([install.url])
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Duplicates

    private func duplicatesSection(_ audit: LlamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Duplicate GGUFs",
                subtitle: "Detected by content fingerprint (size + head/tail hash)"
            ) {
                AnyView(
                    Group {
                        if !audit.duplicateGroups.isEmpty {
                            Button("Trash Duplicates…") {
                                duplicatesPendingDelete = audit.duplicateGroups.flatMap { $0.dropFirst() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                )
            }
            if audit.duplicateGroups.isEmpty {
                Label("No duplicates found.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(Array(audit.duplicateGroups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(group.enumerated()), id: \.offset) { index, file in
                            HStack(spacing: 8) {
                                Image(systemName: index == 0 ? "checkmark.circle" : "doc.on.doc")
                                    .foregroundStyle(index == 0 ? .green : .orange)
                                    .help(index == 0 ? "Kept" : "Duplicate")
                                Text(file.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(Format.bytes(file.size))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(file.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Models

    private func modelsSection(_ audit: LlamaAudit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Models by Location",
                subtitle: "llama.cpp cache, HuggingFace hub, LM Studio, Jan, GPT4All, and custom folders"
            )
            if audit.modelDirs.isEmpty {
                Label("No model directories found.", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(audit.modelDirs) { dir in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(dir.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    StatusBadge(text: dir.source.rawValue, color: .blue)
                                }
                                Text(dir.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.bytes(dir.totalBytes))
                                    .monospacedDigit()
                                if !dir.ggufFiles.isEmpty {
                                    Text("\(dir.ggufFiles.count) GGUF\(dir.ggufFiles.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button {
                                dirPendingDelete = dir
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete folder")
                            Button {
                                TrashService.revealInFinder([dir.url])
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                        ForEach(dir.ggufFiles.prefix(4)) { file in
                            HStack(spacing: 8) {
                                Text(file.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.leading, 26)
                                if let meta = file.meta {
                                    if let quant = meta.quantization {
                                        StatusBadge(text: quant, color: .teal)
                                    }
                                    if let arch = meta.architecture {
                                        StatusBadge(text: arch, color: .blue)
                                    }
                                    if let ctx = meta.contextLength, ctx > 0 {
                                        Text("ctx \(ctx)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Format.bytes(file.size))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Button {
                                    TrashService.revealInFinder([URL(fileURLWithPath: file.path)])
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if dir.ggufFiles.count > 4 {
                            Text("…and \(dir.ggufFiles.count - 4) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 26)
                        }
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning llama.cpp installs and model caches…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
