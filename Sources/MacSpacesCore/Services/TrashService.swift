import AppKit
import Foundation

/// File deletion: Trash by default, permanent deletion behind explicit mode.
public enum TrashService {
    @MainActor
    public static var deleteMode: DeletionMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "deleteMode") ?? DeletionMode.trash.rawValue
            return DeletionMode(rawValue: raw) ?? .trash
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "deleteMode")
        }
    }

    public static func delete(_ urls: [URL], mode: DeletionMode) -> [DeleteOutcome] {
        urls.map { deleteOne($0, mode: mode) }
    }

    public static func deleteOne(_ url: URL, mode: DeletionMode) -> DeleteOutcome {
        if let refusal = refusalReason(for: url) {
            return DeleteOutcome(url: url, success: false, message: refusal)
        }
        do {
            switch mode {
            case .trash:
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            case .permanent:
                try FileManager.default.removeItem(at: url)
            }
            return DeleteOutcome(url: url, success: true, message: nil)
        } catch {
            return DeleteOutcome(url: url, success: false, message: error.localizedDescription)
        }
    }

    /// Refuses to delete filesystem roots and the home directory itself —
    /// a guard against pathological configured paths, not user error (the UI
    /// always confirms first).
    public static func refusalReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        if path == "/" {
            return "Refusing to delete the filesystem root."
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home {
            return "Refusing to delete the home directory itself."
        }
        return nil
    }

    /// Reveals `urls` in Finder. Falls back to the nearest existing ancestor
    /// when an item no longer exists (deleted since the scan, or a synthetic
    /// path Finder cannot show). Returns false when the reveal had to fall
    /// back — callers can surface that in the feedback strip.
    @discardableResult
    public static func revealInFinder(_ urls: [URL]) -> Bool {
        let targets = urls.compactMap { revealTarget(for: $0) }
        guard !targets.isEmpty else { return false }
        NSWorkspace.shared.activateFileViewerSelecting(targets)
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The URL itself when it exists, else its nearest existing ancestor,
    /// else nil.
    public static func revealTarget(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for _ in 0..<32 {
            if FileManager.default.fileExists(atPath: current.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == home {
                return nil
            }
            current = parent
        }
        return nil
    }
}
