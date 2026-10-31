import Foundation
import Combine

/// Polls user-configured folders on a fixed interval and raises an alert when
/// a folder grows past its threshold. (Polling rather than FSEvents for v1:
/// correct, dependency-free, and cheap for the handful of watched folders.)
public final class WatchService: ObservableObject {
    public static let foldersKey = "watchFolders"
    public static let thresholdKey = "watchThresholdGB"

    @Published public private(set) var alerts: [WatchAlert] = []
    @Published public private(set) var lastChecked: Date?

    private var timer: Timer?
    private var inFlight = false

    public init() {
        // Re-check every 5 minutes.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    public var folders: [URL] {
        Self.configuredFolders()
    }

    public static func configuredFolders() -> [URL] {
        let raw = UserDefaults.standard.string(forKey: Self.foldersKey) ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser
        return raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.map { raw in
            if raw.hasPrefix("~/") { return home.appendingPathComponent(String(raw.dropFirst(2))) }
            return URL(fileURLWithPath: raw)
        }
    }

    public var thresholdBytes: Int64 {
        let gb = UserDefaults.standard.double(forKey: Self.thresholdKey)
        return gb > 0 ? Int64(gb * 1_000_000_000) : 10_000_000_000 // default 10 GB
    }

    public static func setFolders(_ folders: [String]) {
        UserDefaults.standard.set(folders.joined(separator: "\n"), forKey: foldersKey)
    }

    public static func setThresholdGB(_ gb: Double) {
        UserDefaults.standard.set(gb, forKey: thresholdKey)
    }

    /// Re-sizes every watched folder; replaces alerts with current violations.
    public func check() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let threshold = thresholdBytes
        let checked = folders
        let newAlerts: [WatchAlert] = await Task.detached(priority: .utility) {
            checked.compactMap { folder -> WatchAlert? in
                let size = DiskScanner.sequentialSize(of: folder)
                guard size >= threshold else { return nil }
                return WatchAlert(folder: folder.path, bytes: size, thresholdBytes: threshold, date: Date())
            }
        }.value

        self.alerts = newAlerts
        self.lastChecked = Date()
    }
}
