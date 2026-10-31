import Foundation
import CoreGraphics

// MARK: - Space map layout (squarified treemap)

/// One rendered rectangle of the space map. `node` is nil for aggregate tiles
/// ("Other") that bundle culled small children — those cannot be zoomed or
/// deleted individually.
public struct SpaceTile: Identifiable {
    public let path: String
    public let name: String
    public let rect: CGRect
    public let depth: Int
    /// Index of the depth-0 ancestor among its siblings — drives tile color.
    public let topIndex: Int
    public let isAggregate: Bool
    public let node: DiskNode?

    public var id: String {
        "\(path)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width))x\(Int(rect.height))"
    }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk) over a DiskNode tree.
///
/// Design constraints that keep the map readable:
/// - Children whose tile would fall below `minTile` points per side are
///   aggregated into a single gray "Other" tile instead of being rendered
///   as slivers.
/// - Subdivision stops at `maxDepth` and once `maxTiles` tiles exist —
///   deeper content stays visually inside its parent tile.
/// - Tiles at depth 0 determine hue; deeper levels darken, so color answers
///   "which top-level branch am I in" at every zoom level.
public enum SpaceMapLayout {
    public static let minTile: CGFloat = 10
    public static let maxDepth = 6
    public static let maxTiles = 800

    /// Computes the tile rectangles for `node` rendered into `size`.
    public static func tiles(for node: DiskNode, in size: CGSize) -> [SpaceTile] {
        guard size.width >= 2 * minTile, size.height >= 2 * minTile else { return [] }
        var tiles: [SpaceTile] = []
        var budget = maxTiles
        layout(
            node: node,
            rect: CGRect(origin: .zero, size: size),
            depth: 0,
            topIndex: 0,
            tiles: &tiles,
            budget: &budget
        )
        return tiles
    }

    // MARK: - Recursive layout

    private static func layout(
        node: DiskNode, rect: CGRect, depth: Int, topIndex: Int,
        tiles: inout [SpaceTile], budget: inout Int
    ) {
        guard budget > 0 else { return }

        // Leaf cases: depth exhausted, nothing inside, or physically too
        // small to subdivide further.
        let children = node.children.filter { $0.totalBytes > 0 }
        guard depth < maxDepth,
              !children.isEmpty,
              rect.width >= 2 * minTile, rect.height >= 2 * minTile
        else {
            emit(node: node, name: node.name, rect: rect, depth: depth,
                 topIndex: topIndex, aggregate: false, tiles: &tiles, budget: &budget)
            return
        }

        // Culled-by-area children roll into one "Other" tile. Keep at least
        // the largest child so the map never collapses into a single blob.
        // A lone sub-threshold child produces a sub-minTile Other, which is
        // simply omitted — an aggregate becomes visible once several small
        // children sum above the minimum.
        let total = max(1, children.reduce(Int64(0)) { $0 + $1.totalBytes })
        let minFraction = Double(minTile * minTile) / Double(rect.width * rect.height)
        let sorted = children.sorted { $0.totalBytes > $1.totalBytes }
        var kept = Array(sorted.prefix(1))
        var culled: [DiskNode] = []
        for child in sorted.dropFirst() {
            if Double(child.totalBytes) / Double(total) >= minFraction {
                kept.append(child)
            } else {
                culled.append(child)
            }
        }

        struct Entry {
            let name: String
            let path: String
            let value: Double
            let node: DiskNode?
            let isAggregate: Bool
        }

        // Squarify, then re-cull any kept child that ended up below minTile
        // on an axis (siblings can squeeze a big-enough-by-area child into a
        // thin strip). Iterating lets the Other tile absorb them and reflow.
        var entries: [Entry] = []
        var rects: [CGRect] = []
        for _ in 0..<3 {
            entries = kept.map {
                Entry(name: $0.name, path: $0.path, value: Double($0.totalBytes), node: $0, isAggregate: false)
            }
            let culledBytes = culled.reduce(Int64(0)) { $0 + $1.totalBytes }
            if !culled.isEmpty {
                entries.append(Entry(name: "Other", path: node.path + "/__other__",
                                     value: Double(culledBytes), node: nil, isAggregate: true))
            }
            entries.sort { $0.value > $1.value }
            rects = squarify(entries.map { $0.value }, in: rect)

            var violated = false
            for (index, entry) in entries.enumerated() where !entry.isAggregate {
                let r = rects[index]
                if r.width < minTile || r.height < minTile, let node = entry.node {
                    violated = true
                    culled.append(node)
                    kept.removeAll { $0.path == node.path }
                }
            }
            if !violated { break }
        }
        for (entry, tileRect) in zip(entries, rects) {
            guard budget > 0 else { break }
            budget -= 1
            emit(node: entry.node, name: entry.name, rect: tileRect, depth: depth,
                 topIndex: topIndex, aggregate: entry.isAggregate, tiles: &tiles, budget: &budget)

            if let child = entry.node, child.isDirectory, !child.children.isEmpty {
                layout(
                    node: child,
                    rect: tileRect.insetBy(dx: 1, dy: 1),
                    depth: depth + 1,
                    topIndex: topIndex,
                    tiles: &tiles,
                    budget: &budget
                )
            }
        }
    }

    private static func emit(
        node: DiskNode?, name: String, rect: CGRect, depth: Int, topIndex: Int,
        aggregate: Bool, tiles: inout [SpaceTile], budget: inout Int
    ) {
        guard rect.width >= 1, rect.height >= 1, budget >= 0 else { return }
        budget -= 1
        tiles.append(SpaceTile(
            path: node?.path ?? name,
            name: name,
            rect: rect,
            depth: depth,
            topIndex: topIndex,
            isAggregate: aggregate,
            node: node
        ))
    }

    // MARK: - Squarify core

    /// Lays out `values` (sorted descending for best results) into `bounds`,
    /// returning one rect per value in the same order. Total area of the
    /// returned rects equals the bounds area.
    public static func squarify(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else {
            return values.map { _ in CGRect.zero }
        }

        // Normalize to pixel areas.
        let scale = Double(bounds.width * bounds.height) / total
        var areas = values.map { $0 * scale }
        var rects = [CGRect](repeating: .zero, count: areas.count)
        var rect = bounds
        var offset = 0

        while offset < areas.count {
            let side = Double(min(rect.width, rect.height))
            guard side > 0 else {
                for i in offset..<areas.count { rects[i] = .zero }
                break
            }

            // Grow the row while the worst aspect ratio improves.
            var row: [Double] = [areas[offset]]
            var consumed = 1
            while offset + consumed < areas.count {
                let candidate = row + [areas[offset + consumed]]
                if worst(candidate, side) <= worst(row, side) {
                    row = candidate
                    consumed += 1
                } else {
                    break
                }
            }

            let rowArea = row.reduce(0, +)
            if rect.width >= rect.height {
                // Vertical strip on the left, items stacked top→bottom.
                let thickness = CGFloat(rowArea / Double(rect.height))
                var y = rect.minY
                for (i, a) in row.enumerated() {
                    let h = CGFloat(a) / max(thickness, .leastNormalMagnitude)
                    rects[offset + i] = CGRect(x: rect.minX, y: y, width: thickness, height: h).intersection(bounds)
                    y += h
                }
                rect = CGRect(x: rect.minX + thickness, y: rect.minY,
                              width: rect.width - thickness, height: rect.height)
            } else {
                // Horizontal strip on top, items laid left→right.
                let thickness = CGFloat(rowArea / Double(rect.width))
                var x = rect.minX
                for (i, a) in row.enumerated() {
                    let w = CGFloat(a) / max(thickness, .leastNormalMagnitude)
                    rects[offset + i] = CGRect(x: x, y: rect.minY, width: w, height: thickness).intersection(bounds)
                    x += w
                }
                rect = CGRect(x: rect.minX, y: rect.minY + thickness,
                              width: rect.width, height: rect.height - thickness)
            }
            offset += consumed
        }
        return rects
    }

    /// Worst aspect ratio of any item in a row laid along a side of length `w`
    /// (Bruls et al. eq. 3): max(w²·r⁺/s², s²/(w²·r⁻)).
    static func worst(_ row: [Double], _ w: Double) -> Double {
        guard !row.isEmpty else { return .infinity }
        let s = row.reduce(0, +)
        guard s > 0, w > 0 else { return .infinity }
        let rMax = row.max() ?? 0
        let rMin = row.min() ?? 0
        guard rMin > 0 else { return .infinity }
        let w2 = w * w
        return max((w2 * rMax) / (s * s), (s * s) / (w2 * rMin))
    }
}
