import Foundation
import Testing
@testable import FissionCore

struct ProjectPathQueryTests {
    @Test func pathQueriesStartWithDotSlashTildeOrRoot() {
        #expect(ProjectPathQuery.isPathQuery("~/src"))
        #expect(ProjectPathQuery.isPathQuery("/work"))
        #expect(ProjectPathQuery.isPathQuery("./lib"))
        #expect(!ProjectPathQuery.isPathQuery("fission"))
        #expect(!ProjectPathQuery.isPathQuery("~"))
    }

    @Test func listingTargetSplitsDirectoryAndPrefix() {
        let slash = ProjectPathQuery.listingTarget(query: "/work/fis", relativeBase: nil)
        #expect(slash?.directory == "/work")
        #expect(slash?.namePrefix == "fis")

        let children = ProjectPathQuery.listingTarget(query: "~/src/", relativeBase: nil)
        #expect(children?.directory == "~/src")
        #expect(children?.namePrefix == "")

        let root = ProjectPathQuery.listingTarget(query: "/", relativeBase: nil)
        #expect(root?.directory == "/")
        #expect(root?.namePrefix == "")
    }

    @Test func remoteQueriesWithoutAPrefixAreLookedUpUnderHome() {
        #expect(ProjectPathQuery.normalizeRemoteQuery("") == "~/")
        #expect(ProjectPathQuery.normalizeRemoteQuery("~") == "~/")
        #expect(ProjectPathQuery.normalizeRemoteQuery("src") == "~/src")
        #expect(ProjectPathQuery.normalizeRemoteQuery("/work/fission") == "/work/fission")
    }

    @Test func exactDirectoryNameBrowsesIntoThatPath() {
        let target = ProjectPathQuery.resolvedListingTarget(
            query: "/work/fission",
            relativeBase: nil,
            exactChildNames: { directory in
                directory == "/work" ? ["fission", "notes"] : nil
            }
        )
        #expect(target?.directory == "/work/fission")
        #expect(target?.namePrefix == "")
    }

    @Test func pickerListsCurrentDirectoryThenAvailableChildren() {
        #expect(
            ProjectPathQuery.pickerPaths(
                directory: "/work/fission",
                namePrefix: "",
                childNames: ["src", "Packages"]
            ) == ["/work/fission", "/work/fission/Packages", "/work/fission/src"]
        )
        #expect(
            ProjectPathQuery.pickerPaths(
                directory: "~",
                namePrefix: "",
                childNames: ["src", "work"]
            ) == ["~/src", "~/work"]
        )
    }

    @Test func relativeQueriesExpandAgainstTheBase() {
        let target = ProjectPathQuery.listingTarget(query: "./fi", relativeBase: "/work")
        #expect(target?.directory == "/work")
        #expect(target?.namePrefix == "fi")

        let dir = ProjectPathQuery.listingTarget(query: "./", relativeBase: "/work/fission")
        #expect(dir?.directory == "/work/fission")
        #expect(dir?.namePrefix == "")
    }

    @Test func childProjectsFilterAndJoin() {
        let paths = ProjectPathQuery.childProjects(
            directory: "~/src",
            names: ["Fission", "notes", "other"],
            namePrefix: "fi"
        )
        #expect(paths == ["~/src/Fission"])
        #expect(ProjectPathQuery.join("/", "work") == "/work")
        #expect(ProjectPathQuery.lastComponent("~/src/Fission") == "Fission")
    }

    @Test func completedInputKeepsQueryPrefixes() {
        #expect(
            ProjectPathQuery.completedInput(
                query: "/work/fi",
                path: "/work/fission",
                homePath: "/Users/ada",
                relativeBase: nil
            ) == "/work/fission/"
        )
        #expect(
            ProjectPathQuery.completedInput(
                query: "~/src/fi",
                path: "/Users/ada/src/fission",
                homePath: "/Users/ada",
                relativeBase: nil
            ) == "~/src/fission/"
        )
        #expect(
            ProjectPathQuery.completedInput(
                query: "./fi",
                path: "/work/fission",
                homePath: nil,
                relativeBase: "/work"
            ) == "./fission/"
        )
        #expect(
            ProjectPathQuery.completedInput(
                query: "~/src/fi",
                path: "~/src/fission",
                homePath: nil,
                relativeBase: nil
            ) == "~/src/fission/"
        )
    }

    @Test func recentsDedupeAndFilter() {
        let paths = ProjectPathQuery.recentProjects(
            ["/work/fission/", "/work/fission", "~/notes", "/tmp/other"],
            matching: "fis"
        )
        #expect(paths == ["/work/fission"])
    }
}

struct SSHDirectoryListingTests {
    @Test func buildsBatchModeSSHArguments() {
        let machine = RemoteMachine(
            name: "Studio",
            username: "ada",
            host: "gpu.local",
            sshPort: 2_222
        )
        let arguments = SSHDirectoryListing.processArguments(
            machine: machine,
            directory: "~/src/fission"
        )

        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("2222"))
        #expect(arguments.contains("ada@gpu.local"))
        #expect(arguments.last?.contains("~/src/fission") == true)
        #expect(!arguments.contains(where: { $0.contains("password") }))
    }

    @Test func parsesDirectoryNamesFromFindOutput() {
        let names = SSHDirectoryListing.parseOutput("""
        fission
        notes
        .hidden
        fission

        """)
        #expect(names == ["fission", "notes"])
    }

    @Test func parsesFixtureJSON() {
        let map = SSHDirectoryListing.parseFixtureJSON(
            #"{"/work":["fission","notes"],"~/src":["app"]}"#
        )
        #expect(map?["/work"] == ["fission", "notes"])
        #expect(map?["~/src"] == ["app"])
    }
}
