import FissionCore
import Foundation

struct ProjectPath: Identifiable, Hashable {
    let path: String
    let displayPath: String

    var id: String { path }
    var name: String {
        let last = ProjectPathQuery.lastComponent(path)
        return last.isEmpty ? path : last
    }

    var url: URL { URL(fileURLWithPath: path) }

    init(path: String, displayPath: String? = nil) {
        self.path = path
        self.displayPath = displayPath ?? path
    }

    init(url: URL) {
        let path = url.standardizedFileURL.path
        self.path = path
        self.displayPath = Self.abbreviated(path)
    }

    private static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum ProjectPathResolver {
    static func projects(matching query: String, recentPaths: [String]) -> [ProjectPath] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectPathQuery.isPathQuery(trimmedQuery) else {
            return recentProjects(recentPaths, matching: trimmedQuery)
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let relativeBase = recentPaths.first ?? homePath
        let relative = ProjectPathQuery.expandRelative(trimmedQuery, base: relativeBase)
        let expanded = relative.hasPrefix("~")
            ? (relative as NSString).expandingTildeInPath
            : relative
        let splitQuery = trimmedQuery.hasSuffix("/") && !expanded.hasSuffix("/")
            ? expanded + "/"
            : expanded
        guard let target = ProjectPathQuery.listingTarget(
            query: splitQuery,
            relativeBase: nil
        ) else {
            return []
        }

        let directoryURL = URL(fileURLWithPath: target.directory).standardizedFileURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let names = urls.compactMap { url -> String? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values?.isDirectory == true, values?.isHidden != true else { return nil }
            return url.lastPathComponent
        }

        return ProjectPathQuery.childProjects(
            directory: directoryURL.path,
            names: names,
            namePrefix: target.namePrefix
        ).map { ProjectPath(url: URL(fileURLWithPath: $0)) }
    }

    private static func recentProjects(_ paths: [String], matching query: String) -> [ProjectPath] {
        ProjectPathQuery.recentProjects(paths, matching: query)
            .compactMap { path in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                guard exists, isDirectory.boolValue else { return nil }
                return ProjectPath(url: URL(fileURLWithPath: path))
            }
    }
}

enum RemoteProjectPathResolver {
    static func projects(
        matching query: String,
        recentPaths: [String],
        childNames: [String]?,
        relativeBase: String?
    ) -> [ProjectPath] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectPathQuery.isPathQuery(trimmedQuery) else {
            return ProjectPathQuery.recentProjects(recentPaths, matching: trimmedQuery)
                .map { ProjectPath(path: $0) }
        }

        guard let target = ProjectPathQuery.listingTarget(
            query: trimmedQuery,
            relativeBase: relativeBase
        ) else {
            return typedPathCandidate(trimmedQuery).map { [$0] } ?? []
        }

        if let childNames {
            let listed = ProjectPathQuery.childProjects(
                directory: target.directory,
                names: childNames,
                namePrefix: target.namePrefix
            ).map { ProjectPath(path: $0) }
            if listed.isEmpty {
                return typedPathCandidate(trimmedQuery).map { [$0] } ?? []
            }
            return listed
        }

        return typedPathCandidate(trimmedQuery).map { [$0] } ?? []
    }

    static func typedPathCandidate(_ query: String) -> ProjectPath? {
        guard let path = RemoteMachine.normalizedProjectPath(query),
              path != "/",
              path != "~",
              path != "." else {
            return nil
        }
        return ProjectPath(path: path)
    }
}

enum RecentProjectPaths {
    private static let key = "recentProjectPaths"
    private static let limit = 9

    static func load() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        if saved.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let projects = home.appending(path: "Projects")
            return FileManager.default.fileExists(atPath: projects.path)
                ? [projects.path, home.path]
                : [home.path]
        }
        return saved
    }

    static func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = load().filter { $0 != path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }
}
