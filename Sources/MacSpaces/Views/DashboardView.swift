import Charts
import SwiftUI
import MacSpacesCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: SidebarItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                volumeSection
                auditSummarySection
                watchAlertsSection
                if let root = model.diskRoot {
                    topConsumersSection(root: root)
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Volumes

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage").font(.headline)
            HStack(alignment: .top, spacing: 24) {
                if let volume = model.volumeMonitor.primaryVolume {
                    UsageRing(
                        usedFraction: volume.usedFraction,
                        centerTitle: "\(Int(volume.usedFraction * 100))%",
                        centerSubtitle: "of \(Format.bytes(volume.totalCapacity))"
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledRow(label: "Volume", value: volume.name)
                        LabeledRow(label: "Used", value: Format.bytes(volume.usedCapacity))
                        LabeledRow(label: "Free", value: Format.bytes(volume.availableCapacity), emphasis: true)
                        LabeledRow(label: "Total", value: Format.bytes(volume.totalCapacity))
                        Button {
                            selection = .disk
                            if model.diskRoot == nil && !model.isScanning {
                                model.scanDisk()
                            }
                        } label: {
                            Label("Analyze disk usage", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
    }

    // MARK: - Audit summaries

    private var auditSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI model audits").font(.headline)
            HStack(spacing: 12) {
                auditCard(
                    title: "Ollama",
                    systemImage: "pawprint",
                    tint: .purple
                ) {
                    if let audit = model.ollamaAudit {
                        if audit.orphanedBlobs.isEmpty {
                            StatValue("No orphaned blobs", detail: "\(audit.models.count) models · \(Format.bytes(audit.modelsBytes))")
                        } else {
                            StatValue(Format.bytes(audit.orphanedBytes), detail: "reclaimable from \(audit.orphanedBlobs.count) orphaned blobs")
                        }
                    } else {
                        StatValue("Not audited", detail: "Run the Ollama audit")
                    }
                }
                auditCard(
                    title: "llama.cpp",
                    systemImage: "cpu",
                    tint: .teal
                ) {
                    if let audit = model.llamaAudit {
                        if audit.duplicateGroups.isEmpty {
                            StatValue(Format.bytes(audit.ggufBytes), detail: "\(audit.modelDirs.count) model locations · \(audit.installs.count) installs")
                        } else {
                            StatValue(Format.bytes(audit.duplicateReclaimableBytes), detail: "reclaimable from duplicate GGUFs")
                        }
                    } else {
                        StatValue("Not audited", detail: "Run the llama.cpp audit")
                    }
                }
                auditCard(
                    title: "Caches",
                    systemImage: "archivebox",
                    tint: .pink
                ) {
                    if let audit = model.cachesAudit {
                        StatValue(Format.bytes(audit.totalBytes), detail: "developer caches, rebuilt on demand")
                    } else {
                        StatValue("Not audited", detail: "Run the caches audit")
                    }
                }
            }
        }
    }

    private func auditCard<Content: View>(
        title: String, systemImage: String, tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            content()
            HStack(spacing: 8) {
                Button("Audit \(title)") {
                    switch title {
                    case "Ollama":
                        model.runOllamaAudit()
                        selection = .ollama
                    case "llama.cpp":
                        model.runLlamaAudit()
                        selection = .llama
                    default:
                        model.runCachesAudit()
                        selection = .caches
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isAuditing(title))
                if isAuditing(title) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func isAuditing(_ title: String) -> Bool {
        switch title {
        case "Ollama": return model.isAuditingOllama
        case "llama.cpp": return model.isAuditingLlama
        default: return model.isAuditingCaches
        }
    }

    private struct StatValue: View {
        let main: String
        let detail: String

        init(_ main: String, detail: String) {
            self.main = main
            self.detail = detail
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(main).font(.title2.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Watch alerts (feature: folder monitoring)

    @ViewBuilder
    private var watchAlertsSection: some View {
        if !model.watch.alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Watched Folder Alerts",
                    subtitle: "Folders that grew past their size threshold"
                )
                ForEach(model.watch.alerts) { alert in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.humanFolder)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("threshold \(Format.bytes(alert.thresholdBytes)) · checked \(alert.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(alert.bytes))
                            .monospacedDigit()
                            .font(.callout.weight(.semibold))
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Top consumers

    private func topConsumersSection(root: DiskNode) -> some View {
        let top = Array(root.children.sorted { $0.totalBytes > $1.totalBytes }.prefix(8))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Largest folders in “\(root.name)”").font(.headline)
                Spacer()
                if let date = model.lastScanDate {
                    Text("Scanned \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Open Disk Usage") { selection = .disk }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Chart(top) { node in
                BarMark(
                    x: .value("Size", node.totalBytes),
                    y: .value("Folder", node.name)
                )
                .foregroundStyle(by: .value("Folder", node.name))
                .annotation(position: .trailing) {
                    Text(Format.bytes(node.totalBytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(height: CGFloat(top.count) * 26)
            .opacity(0.9)

            Text("Total: \(Format.bytes(root.totalBytes)) in \(root.itemCount) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var emphasis: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(emphasis ? .bold : .medium)
                .monospacedDigit()
        }
        .frame(maxWidth: 320)
    }
}
