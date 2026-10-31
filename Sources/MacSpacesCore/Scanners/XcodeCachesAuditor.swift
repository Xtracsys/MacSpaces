import Foundation

/// Audits reclaimable developer caches: Xcode DerivedData and Archives,
/// device support, simulator caches, and SwiftPM caches.
public struct XcodeCachesAuditor {
    public let homeDirectory: URL

    public init(homeDirectory: URL? = nil) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// (path, category) pairs — every location is safe to delete wholesale;
    /// Xcode/SwiftPM rebuild and re-download as needed.
    public static let locations: [(String, CacheCategory)] = [
        ("~/Library/Developer/Xcode/DerivedData", .xcodeDerivedData),
        ("~/Library/Developer/Xcode/Archives", .xcodeArchives),
        ("~/Library/Developer/Xcode/iOS DeviceSupport", .deviceSupport),
        ("~/Library/Developer/CoreSimulator/Caches", .simulatorCaches),
        ("~/Library/Developer/CoreSimulator/Profiles/.trash", .simulatorCaches),
        ("~/Library/Caches/org.swift.swiftpm", .swiftPM),
        ("~/Library/org.swift.swiftpm", .swiftPM),
    ]

    public func audit() -> CachesAudit {
        var audit = CachesAudit()
        let fm = FileManager.default

        for (rawPath, category) in Self.locations {
            let root = Self.expanding(rawPath, home: homeDirectory)
            guard fm.fileExists(atPath: root.path) else { continue }

            if category == .xcodeDerivedData || category == .xcodeArchives {
                // Per-project subdirectories, so individual cleanups are possible.
                let children = (try? fm.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
                )) ?? []
                for child in children where child.lastPathComponent != ".DS_Store" {
                    let size = DiskScanner.sequentialSize(of: child)
                    guard size > 0 else { continue }
                    audit.items.append(CacheItem(
                        name: Self.prettyDerivedName(child.lastPathComponent),
                        path: child.path,
                        category: category,
                        size: size
                    ))
                }
            } else {
                let size = DiskScanner.sequentialSize(of: root)
                guard size > 0 else { continue }
                audit.items.append(CacheItem(
                    name: root.lastPathComponent,
                    path: root.path,
                    category: category,
                    size: size
                ))
            }
        }

        audit.items.sort { $0.size > $1.size }
        return audit
    }

    /// DerivedData dirs are named "AppName-<hash>" — strip the hash for display.
    static func prettyDerivedName(_ raw: String) -> String {
        guard let dash = raw.lastIndex(of: "-") else { return raw }
        let suffix = raw[raw.index(after: dash)...]
        if suffix.count == 12, suffix.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return String(raw[..<dash])
        }
        return raw
    }

    static func expanding(_ path: String, home: URL) -> URL {
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }
}
