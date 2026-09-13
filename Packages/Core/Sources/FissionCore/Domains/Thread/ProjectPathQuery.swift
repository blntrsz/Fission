import Foundation

/// Path-shaped project search used by the New Thread picker.
public enum ProjectPathQuery {
    public static func isPathQuery(_ query: String) -> Bool {
        query.hasPrefix("./") || query.hasPrefix("~/") || query.hasPrefix("/")
    }

    /// Directory to list and the filename prefix to match.
    public static func listingTarget(
        query: String,
        relativeBase: String?
    ) -> (directory: String, namePrefix: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPathQuery(trimmed) else { return nil }

        let expanded = expandRelative(trimmed, base: relativeBase)
        if trimmed.hasSuffix("/") {
            return (stripTrailingSlashes(expanded), "")
        }
        return (parentDirectory(expanded), lastComponent(expanded))
    }

    public static func expandRelative(_ path: String, base: String?) -> String {
        guard path.hasPrefix("./") else { return path }
        let rest = String(path.dropFirst(2))
        guard let base, !base.isEmpty else { return path }
        if rest.isEmpty || rest == "/" {
            return stripTrailingSlashes(base)
        }
        return join(stripTrailingSlashes(base), rest)
    }

    public static func join(_ directory: String, _ child: String) -> String {
        if child.isEmpty { return directory }
        if directory == "/" {
            return child.hasPrefix("/") ? child : "/" + child
        }
        if directory.hasSuffix("/") {
            return directory + child
        }
        return directory + "/" + child
    }

    public static func parentDirectory(_ path: String) -> String {
        let trimmed = stripTrailingSlashes(path)
        if trimmed == "/" || trimmed == "~" || trimmed == "." { return trimmed }
        guard let slash = trimmed.lastIndex(of: "/") else { return "." }
        let parent = String(trimmed[..<slash])
        if parent.isEmpty { return "/" }
        return parent
    }

    public static func lastComponent(_ path: String) -> String {
        let trimmed = stripTrailingSlashes(path)
        if trimmed == "/" { return "/" }
        if trimmed == "~" { return "~" }
        guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
        let name = String(trimmed[trimmed.index(after: slash)...])
        return name.isEmpty ? trimmed : name
    }

    public static func matchesPrefix(_ name: String, prefix: String) -> Bool {
        prefix.isEmpty
            || name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    public static func matchesRecent(_ path: String, query: String) -> Bool {
        query.isEmpty
            || lastComponent(path).localizedCaseInsensitiveContains(query)
            || path.localizedCaseInsensitiveContains(query)
    }

    /// Tab-complete a selected path, keeping `./` and `~/` prefixes from the query.
    public static func completedInput(
        query: String,
        path: String,
        homePath: String?,
        relativeBase: String?
    ) -> String {
        let withSlash = path.hasSuffix("/") || path == "/" ? path : path + "/"

        if query.hasPrefix("./"), let relativeBase {
            let base = stripTrailingSlashes(relativeBase)
            if path == base { return "./" }
            let prefix = base + "/"
            if path.hasPrefix(prefix) {
                return "./" + path.dropFirst(prefix.count) + (path.hasSuffix("/") ? "" : "/")
            }
        }

        if let homePath {
            let home = stripTrailingSlashes(homePath)
            if query.hasPrefix("~/") || (!query.hasPrefix("/") && path.hasPrefix(home + "/"))
                || path == home
            {
                if path == home { return "~/" }
                if path.hasPrefix(home) {
                    return "~" + path.dropFirst(home.count) + (path.hasSuffix("/") ? "" : "/")
                }
            }
        }

        if path.hasPrefix("~") {
            return withSlash
        }

        return withSlash
    }

    public static func recentProjects(
        _ paths: [String],
        matching query: String,
        limit: Int = 9
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            guard let normalized = MoshCommand.normalizedDirectory(path) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            guard matchesRecent(normalized, query: query) else { continue }
            result.append(normalized)
            if result.count == limit { break }
        }
        return result
    }

    public static func childProjects(
        directory: String,
        names: [String],
        namePrefix: String,
        limit: Int = 50
    ) -> [String] {
        names
            .filter { matchesPrefix($0, prefix: namePrefix) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { join(directory, $0) }
    }

    public static func stripTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
