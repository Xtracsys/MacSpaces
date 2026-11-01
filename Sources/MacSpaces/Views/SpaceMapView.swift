import SwiftUI
import MacSpacesCore

/// The interactive treemap: squarified layout, color per top-level branch,
/// click-to-zoom with breadcrumbs, hover info bar, and a clickable legend.
struct SpaceMapView: View {
    @EnvironmentObject private var model: AppModel
    /// The scan root (never changes during a session).
    let rootNode: DiskNode

    @State private var zoomPath: String?
    @State private var hovered: SpaceTile?
    @State private var pendingDelete: DiskNode?

    // MARK: - Derived state

    /// The node the map currently shows. Falls back to the scan root when the
    /// zoomed subtree disappears (e.g. after a delete or rescan).
    private var displayRoot: DiskNode {
        guard let zoomPath else { return rootNode }
        if let found = find(path: zoomPath, in: rootNode) { return found }
        return rootNode
    }

    /// Chain from scan root to displayRoot, for the breadcrumb bar.
    private var breadcrumbs: [DiskNode] {
        var chain: [DiskNode] = []
        var current: DiskNode? = rootNode
        while let node = current {
            chain.append(node)
            if node.path == displayRoot.path { break }
            current = node.children.first { displayRoot.path.hasPrefix($0.path + "/") }
        }
        return chain
    }

    private func find(path: String, in node: DiskNode) -> DiskNode? {
        if node.path == path { return node }
        guard path.hasPrefix(node.path + "/") else { return nil }
        for child in node.children {
            if let found = find(path: path, in: child) { return found }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            mapArea
            infoBar
            legendBar
        }
    }

    // MARK: - Map

    private var mapArea: some View {
        GeometryReader { proxy in
            let tiles = SpaceMapLayout.tiles(for: displayRoot, in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    tileView(tile)
                }
                if tiles.isEmpty {
                    Text("Map too small to render — enlarge the window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func tileView(_ tile: SpaceTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        let bytes = tile.node?.totalBytes ?? 0
        shape
            .fill(Self.color(topIndex: tile.topIndex, depth: tile.depth, aggregate: tile.isAggregate))
            .overlay(alignment: .topLeading) { tileLabel(tile) }
            .overlay {
                shape.strokeBorder(
                    hovered?.id == tile.id ? Color.white.opacity(0.85) : .clear,
                    lineWidth: 1.5
                )
            }
            .frame(width: tile.rect.width, height: tile.rect.height)
            .offset(x: tile.rect.minX, y: tile.rect.minY)
            .contentShape(shape)
            .onHover { inside in
                if inside {
                    hovered = tile
                } else if hovered?.id == tile.id {
                    hovered = nil
                }
            }
            .onTapGesture {
                if let node = tile.node, node.isDirectory, !tile.isAggregate {
                    zoomPath = node.path
                }
            }
            .help("\(tile.name) — \(Format.bytes(bytes))\(tile.isAggregate ? " (aggregate)" : "")")
            .contextMenu {
                if let node = tile.node, !tile.isAggregate {
                    if node.isDirectory {
                        Button("Zoom into “\(node.name)”") { zoomPath = node.path }
                    }
                    Button("Reveal in Finder") {
                        if !TrashService.revealInFinder([node.url]) {
                            model.lastDeletionSummary = "Revealed the nearest existing folder — this item is no longer at its scanned path."
                        }
                    }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { pendingDelete = node }
                }
            }
    }

    /// Labels render only when the tile can hold them — the core readability
    /// policy that replaces the old render-everything sliver noise.
    @ViewBuilder
    private func tileLabel(_ tile: SpaceTile) -> some View {
        if tile.rect.width >= 64 && tile.rect.height >= 36 {
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Format.bytes(tile.node?.totalBytes ?? 0))
                    .font(.caption2)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        } else if tile.rect.width >= 40 && tile.rect.height >= 16 {
            Text(tile.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white.opacity(0.9))
                .padding(3)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Breadcrumbs

    @ViewBuilder
    private var breadcrumbBar: some View {
        let chain = breadcrumbs
        HStack(spacing: 4) {
            Image(systemName: "map.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(node.name) {
                    zoomPath = node.path
                }
                .buttonStyle(.borderless)
                .font(index == chain.count - 1 ? .callout.weight(.semibold) : .callout)
                .disabled(index == chain.count - 1)
            }
            Spacer()
            if zoomPath != nil {
                Button {
                    zoomPath = nil
                } label: {
                    Label("Whole map", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Info bar

    @ViewBuilder
    private var infoBar: some View {
        HStack(spacing: 8) {
            if let tile = hovered {
                Circle()
                    .fill(Self.color(topIndex: tile.topIndex, depth: tile.depth, aggregate: tile.isAggregate))
                    .frame(width: 9, height: 9)
                Text(tile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let node = tile.node {
                    let share = displayRoot.totalBytes > 0
                        ? Double(node.totalBytes) / Double(displayRoot.totalBytes) * 100 : 0
                    Text("\(Format.bytes(node.totalBytes)) · \(String(format: "%.1f", share))% of view")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(Format.tildify(node.path))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("aggregate of smaller items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let node = tile.node, node.isDirectory, !tile.isAggregate {
                    Text("click to zoom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("\(displayRoot.name): \(Format.bytes(displayRoot.totalBytes)) · \(displayRoot.itemCount) items — hover a tile for details, click a directory to zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Legend

    @ViewBuilder
    private var legendBar: some View {
        let branches = displayRoot.children
            .filter { $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
        if !branches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(branches.enumerated()), id: \.element.id) { index, node in
                        Button {
                            zoomPath = node.path
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Self.color(topIndex: index, depth: 0, aggregate: false))
                                    .frame(width: 9, height: 9)
                                Text(node.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(Format.bytes(node.totalBytes))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Zoom into “\(node.name)”")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .overlay(alignment: .leading) {
                // Fade hint that the legend scrolls.
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Color

    /// Hue is a stable function of the top-level branch (golden-angle spacing
    /// so neighbors stay distinguishable); depth darkens within the branch.
    static func color(topIndex: Int, depth: Int, aggregate: Bool) -> Color {
        if aggregate {
            return Color(hue: 0, saturation: 0, brightness: max(0.55, 0.8 - Double(depth) * 0.04))
        }
        // Start the ramp at blue — hue 0 (red) reads as an error state when
        // one branch dominates the map.
        let hue = (0.55 + Double(topIndex) * 0.38).truncatingRemainder(dividingBy: 1.0)
        return Color(
            hue: hue,
            saturation: 0.45 + min(0.2, Double(depth) * 0.05),
            brightness: max(0.45, 0.82 - Double(depth) * 0.07)
        )
    }
}
