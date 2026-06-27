import Foundation

enum ConflictStrategy: String, CaseIterable, Identifiable {
    case appendDash = "append_dash_index"
    case appendParentheses = "append_parentheses_index"
    case appendUnderscore = "append_underscore_index"
    case skip = "skip"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appendDash: "追加编号（-2）"
        case .appendParentheses: "追加括号编号（2）"
        case .appendUnderscore: "追加下划线编号（_2）"
        case .skip: "跳过冲突文件"
        }
    }
}

struct RenameRules: Codable {
    var recursive = true
    var extensions = ["jpg", "jpeg", "png", "webp", "avif", "heic", "heif", "tif", "tiff", "raw", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
    var djiEnabled = true
    var prefix = "DJI"
    var removeMiddleTimestamp = true
    var timestampMustFollowPrefix = true
    var keepMarkers = ["-T", "-L"]
    var removeMarkers = ["_D", "-D", "-HDR", "-EDIT", "-Pano", "-Enhanced", "-NR", "-SR"]
    var removeExistingTrailingDashNumber = true
    var conflictStrategy = ConflictStrategy.appendDash.rawValue
    var conflictStartIndex = 2
}

struct RenameItem: Identifiable, Hashable {
    let id = UUID()
    let source: URL
    let target: URL

    func sourceName(relativeTo base: URL) -> String {
        source.path.replacingOccurrences(of: base.path + "/", with: "")
    }

    func targetName(relativeTo base: URL) -> String {
        target.path.replacingOccurrences(of: base.path + "/", with: "")
    }
}

enum RenameEngine {
    static func buildPlan(base: URL, rules: RenameRules) throws -> [RenameItem] {
        let allowed = Set(rules.extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        guard !allowed.isEmpty else { return [] }

        let files = listFiles(base: base, recursive: rules.recursive)
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }

        var taken = Set<String>()
        var plan: [RenameItem] = []
        let strategy = ConflictStrategy(rawValue: rules.conflictStrategy) ?? .appendDash

        for source in files {
            let stem = source.deletingPathExtension().lastPathComponent
            let newStem = rules.djiEnabled ? normalize(stem: stem, rules: rules) : stem
            guard newStem != stem else { continue }

            let target = source.deletingLastPathComponent()
                .appendingPathComponent(newStem)
                .appendingPathExtension(source.pathExtension)

            guard let resolved = resolveConflict(
                source: source,
                target: target,
                taken: taken,
                strategy: strategy,
                sourceStem: newStem,
                startIndex: rules.conflictStartIndex
            ) else {
                continue
            }
            taken.insert(resolved.path)
            if resolved != source {
                plan.append(RenameItem(source: source, target: resolved))
            }
        }
        return plan
    }

    static func apply(_ plan: [RenameItem]) throws {
        let fileManager = FileManager.default
        for item in plan {
            try fileManager.createDirectory(
                at: item.target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: item.source, to: item.target)
        }
    }

    static func writeLog(base: URL, plan: [RenameItem]) throws -> URL {
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sdji-rename")
            .appendingPathComponent("rename_log.csv")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = "base_dir,source,target\n"
        for item in plan {
            text += "\(base.path),\(item.sourceName(relativeTo: base)),\(item.targetName(relativeTo: base))\n"
        }
        try text.write(to: log, atomically: true, encoding: .utf8)
        return log
    }

    static func undoLast() throws -> Int {
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sdji-rename")
            .appendingPathComponent("rename_log.csv")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return 0 }
        let rows = text.split(separator: "\n").dropFirst().compactMap { line -> (URL, URL)? in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { return nil }
            let base = URL(fileURLWithPath: parts[0])
            return (base.appendingPathComponent(parts[1]), base.appendingPathComponent(parts[2]))
        }
        var count = 0
        for (source, target) in rows.reversed() where FileManager.default.fileExists(atPath: target.path) && !FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.moveItem(at: target, to: source)
            count += 1
        }
        return count
    }

    private static func listFiles(base: URL, recursive: Bool) -> [URL] {
        let fileManager = FileManager.default
        if recursive {
            guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { isRegularFile($0) }
        }
        return (try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isRegularFileKey]))?.filter { isRegularFile($0) } ?? []
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func normalize(stem: String, rules: RenameRules) -> String {
        var value = stem
        let original = stem
        var changed = false
        let keep = Set(rules.keepMarkers)
        let remove = Set(rules.removeMarkers)

        if rules.removeMiddleTimestamp && rules.timestampMustFollowPrefix && value.contains("\(rules.prefix)_") {
            let pattern = "^(.*\(NSRegularExpression.escapedPattern(for: rules.prefix))_)(\\d{14}|\\d{8})_(.+)$"
            let updated = value.replacing(pattern: pattern, with: "$1$3")
            if updated != value {
                value = updated
                changed = true
            }
        }

        var suffix = ""
        if !tailHasRemovableUnderscoreMarker(value, remove: remove) {
            let split = splitTailSuffix(value)
            value = split.0
            suffix = split.1
        }

        let first = removeUnderscoreMarkers(value, keep: keep, remove: remove)
        if first != value {
            value = first
            changed = true
        }

        let stripped = stripHyphenChain(value, keep: keep, remove: remove)
        if stripped != value {
            value = stripped
            changed = true
        }

        let second = removeUnderscoreMarkers(value, keep: keep, remove: remove)
        if second != value {
            value = second
            changed = true
        }

        if !suffix.isEmpty {
            value += "_\(suffix)"
        }
        if changed && rules.removeExistingTrailingDashNumber {
            value = value.replacing(pattern: "-\\d+$", with: "")
        }
        return value == original ? original : value
    }

    private static func splitTailSuffix(_ stem: String) -> (String, String) {
        guard let idx = stem.lastIndex(of: "_") else { return (stem, "") }
        let head = String(stem[..<idx])
        let tail = String(stem[stem.index(after: idx)...])
        if tail.range(of: #"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil {
            return (head, tail)
        }
        return (stem, "")
    }

    private static func tailHasRemovableUnderscoreMarker(_ stem: String, remove: Set<String>) -> Bool {
        guard let tail = stem.split(separator: "_").last else { return false }
        if remove.contains("_\(tail)") { return true }
        if let head = tail.split(separator: "-").first {
            return remove.contains("_\(head)")
        }
        return false
    }

    private static func removeUnderscoreMarkers(_ base: String, keep: Set<String>, remove: Set<String>) -> String {
        let parts = base.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return base }
        var kept = [first]
        for token in parts.dropFirst() {
            if remove.contains("_\(token)") { continue }
            if token.contains("-") {
                var split = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                let head = split.removeFirst()
                if remove.contains("_\(head)") {
                    let rest = split.filter { keep.contains("-\($0)") }
                    if !rest.isEmpty {
                        kept[kept.count - 1] += "-" + rest.joined(separator: "-")
                    }
                    continue
                }
            }
            kept.append(token)
        }
        return kept.joined(separator: "_")
    }

    private static func stripHyphenChain(_ base: String, keep: Set<String>, remove: Set<String>) -> String {
        guard let lastUnderscore = base.lastIndex(of: "_") else { return base }
        let searchStart = base.index(after: lastUnderscore)
        guard let hyphen = base[searchStart...].firstIndex(of: "-") else { return base }
        let core = String(base[..<hyphen])
        let chain = base[base.index(after: hyphen)...].split(separator: "-").map(String.init)
        var hitRemove = false
        var kept: [String] = []
        for token in chain {
            if keep.contains("-\(token)") {
                kept.append(token)
            } else if remove.contains("-\(token)") {
                hitRemove = true
            } else if !hitRemove {
                kept.append(token)
            }
        }
        guard hitRemove else { return base }
        return kept.isEmpty ? core : "\(core)-\(kept.joined(separator: "-"))"
    }

    private static func resolveConflict(source: URL, target: URL, taken: Set<String>, strategy: ConflictStrategy, sourceStem: String, startIndex: Int) -> URL? {
        if target == source { return target }
        let fileManager = FileManager.default
        if !taken.contains(target.path) && !fileManager.fileExists(atPath: target.path) {
            return target
        }
        if strategy == .skip { return nil }
        var index = max(2, startIndex)
        while true {
            let name: String
            switch strategy {
            case .appendParentheses: name = "\(sourceStem) (\(index))"
            case .appendUnderscore: name = "\(sourceStem)_\(index)"
            default: name = "\(sourceStem)-\(index)"
            }
            let candidate = target.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(target.pathExtension)
            if !taken.contains(candidate.path) && !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}

private extension String {
    func replacing(pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }
}
