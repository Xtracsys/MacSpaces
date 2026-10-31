import Foundation
import Combine

/// Polls mounted volumes for capacity at a fixed interval.
@MainActor
public final class VolumeMonitor: ObservableObject {
    @Published public private(set) var volumes: [VolumeInfo] = []
    @Published public private(set) var primaryVolume: VolumeInfo?

    private var timer: Timer?

    public init(pollInterval: TimeInterval = 30) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    public func refresh() {
        let fm = FileManager.default
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ], options: [.skipHiddenVolumes]) ?? []

        let info: [VolumeInfo] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            ])
            guard let total = values?.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(
                url: url,
                name: values?.volumeName ?? url.lastPathComponent,
                totalCapacity: Int64(total),
                availableCapacity: Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
            )
        }
        // The root volume ("Macintosh HD") first, then alphabetical.
        volumes = info.sorted { a, b in
            if a.url.path == "/" { return true }
            if b.url.path == "/" { return false }
            return a.name < b.name
        }
        primaryVolume = volumes.first
    }
}
