import Foundation

/// Glob-style ignore rules applied by the disk scanner and GGUF collectors.
/// Patterns live in UserDefaults ("ignorePatterns"), one per line:
///   name        bare name: matches a directory/file of that name anywhere
///   dir/        trailing slash: exclude the directory and everything below it
///   *           matches anything except "/" (within one path segment)
///   **          matches anything including "/"
///   ?           a single character except "/"
///   #comment    lines starting with # are skipped
/// Patterns containing "/" are anchored to the full path.
public final class IgnoreRules {
    public static let shared = IgnoreRules()
    public static let defaultsKey = "ignorePatterns"

    private var patterns: [NSRegularExpression] = []
    private var directoryPrefixes: [String] = []
    private let lock = NSLock()

    private init() {
        refresh()
    }

    /// Per-instance rules for tests; the app uses `shared`.
    public init(forTesting: Bool) {
        // Intentionally does NOT read UserDefaults.
    }

    /// Reloads patterns from UserDefaults. Call after editing in Settings.
    public func refresh() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        setPatterns(raw.split(separator: "\n").map(String.init))
    }

    public func setPatterns(_ lines: [String]) {
        var regexes: [NSRegularExpression] = []
        var prefixes: [String] = []
        // Caps: excludes() runs per file during scans, so pathological input
        // (very long patterns, huge lists) must not degrade the scanner.
        for line in lines.prefix(500) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.count > 256 { continue }
            if trimmed.hasSuffix("/") {
                // Directory rule: exclude the dir and everything under it.
                prefixes.append(trimmed.hasPrefix("/")
                    ? trimmed
                    : "/**/" + trimmed)
            } else if !trimmed.contains("*"), !trimmed.contains("?"), !trimmed.contains("/") {
                // Bare name: treat as a directory name matching anywhere.
                prefixes.append("/**/" + trimmed)
            } else if let regex = Self.compile(trimmed) {
                regexes.append(regex)
            }
        }
        lock.lock()
        patterns = regexes
        directoryPrefixes = prefixes
        lock.unlock()
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return patterns.isEmpty && directoryPrefixes.isEmpty
    }

    /// True when `path` should be skipped by scanners.
    public func excludes(path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        for prefix in directoryPrefixes {
            // "/**/build/" style rules match the directory anywhere.
            let pattern = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            if path == pattern || path.hasPrefix(pattern + "/") { return true }
            if pattern.hasPrefix("/**/") {
                let suffix = String(pattern.dropFirst(4))
                if path.contains("/" + suffix + "/") || path.hasSuffix("/" + suffix) { return true }
            }
        }
        for regex in patterns where regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil {
            return true
        }
        return false
    }

    /// Converts a glob into a regex. Patterns containing "/" are anchored to
    /// the full path; otherwise the pattern may match at any depth (so
    /// "*.tmp" matches temp files anywhere). A single '*' stays within one
    /// path segment ('[^/]*'), '**' crosses slashes ('.*'), and star runs
    /// collapse to one quantifier so pathological patterns cannot backtrack
    /// exponentially (excludes() runs per file during scans).
    static func compile(_ glob: String) -> NSRegularExpression? {
        var body = "^"
        if !glob.contains("/") {
            body += "(?:.*/)?"
        }
        var starRun = 0
        for ch in glob {
            if ch == "*" {
                starRun += 1
                continue
            }
            if starRun > 0 {
                body += starRun == 1 ? "[^/]*" : ".*"
                starRun = 0
            }
            switch ch {
            case "?":
                body += "[^/]"
            case ".", "(", ")", "[", "]", "{", "}", "+", "^", "$", "|", "\\":
                body += "\\" + String(ch)
            default:
                body += String(ch)
            }
        }
        if starRun > 0 {
            body += starRun == 1 ? "[^/]*" : ".*"
        }
        body += "$"
        return try? NSRegularExpression(pattern: body)
    }
}
