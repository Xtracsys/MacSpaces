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

    public static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
