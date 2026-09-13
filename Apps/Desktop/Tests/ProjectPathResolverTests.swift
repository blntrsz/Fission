import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

struct ProjectPathResolverTests {
    @Test func remotePathQueryFiltersChildDirectories() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "/work",
            namePrefix: "fi",
            childNames: ["fission", "notes", "other"],
            typedQuery: "/work/fi",
            recentPaths: ["/work/fission"]
        )

        #expect(projects.map(\.path) == ["/work/fission"])
        #expect(projects.first?.name == "fission")
    }

    @Test func remoteSlashQueryListsCurrentFolderAndChildren() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "~/src",
            namePrefix: "",
            childNames: ["app", "lib"],
            typedQuery: "~/src/",
            recentPaths: []
        )

        #expect(projects.map(\.path) == ["~/src", "~/src/app", "~/src/lib"])
    }

    @Test func remoteExactPathListsWhatIsInside() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "/work/fission",
            namePrefix: "",
            childNames: ["src", "Packages"],
            typedQuery: "/work/fission",
            recentPaths: []
        )

        #expect(projects.map(\.path) == [
            "/work/fission",
            "/work/fission/Packages",
            "/work/fission/src"
        ])
    }

    @Test func remoteFallsBackToTypedPathWhenListingIsEmpty() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "/work",
            namePrefix: "fission",
            childNames: [],
            typedQuery: "/work/fission",
            recentPaths: []
        )

        #expect(projects.map(\.path) == ["/work/fission"])
    }

    @Test func remoteHomeListingUsesAvailableDirectories() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "~",
            namePrefix: "s",
            childNames: ["src", "work"],
            typedQuery: "src",
            recentPaths: []
        )

        #expect(projects.map(\.path) == ["~/src"])
    }
}

struct RemoteDirectoryCatalogTests {
    @Test func fixtureCatalogReturnsConfiguredChildren() async {
        let catalog = MapRemoteDirectoryCatalog(directories: [
            "/work": ["fission", "notes"]
        ])
        let machine = RemoteMachine(name: "Studio", username: "ada", host: "gpu.example")

        let names = await catalog.childDirectories(on: machine, in: "/work/")
        #expect(names == ["fission", "notes"])
    }
}
