import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

struct ProjectPathResolverTests {
    @Test func remotePathQueryFiltersChildDirectories() {
        let projects = RemoteProjectPathResolver.projects(
            matching: "/work/fi",
            recentPaths: ["/work/fission"],
            childNames: ["fission", "notes", "other"],
            relativeBase: "/work/fission"
        )

        #expect(projects.map(\.path) == ["/work/fission"])
        #expect(projects.first?.name == "fission")
    }

    @Test func remoteSlashQueryListsChildren() {
        let projects = RemoteProjectPathResolver.projects(
            matching: "~/src/",
            recentPaths: [],
            childNames: ["app", "lib"],
            relativeBase: nil
        )

        #expect(projects.map(\.path) == ["~/src/app", "~/src/lib"])
    }

    @Test func remoteEmptyQueryUsesRecents() {
        let projects = RemoteProjectPathResolver.projects(
            matching: "fis",
            recentPaths: ["/work/fission", "/tmp/notes"],
            childNames: nil,
            relativeBase: nil
        )

        #expect(projects.map(\.path) == ["/work/fission"])
    }

    @Test func remoteFallsBackToTypedPathWhenListingIsEmpty() {
        let projects = RemoteProjectPathResolver.projects(
            matching: "/work/fission",
            recentPaths: [],
            childNames: [],
            relativeBase: nil
        )

        #expect(projects.map(\.path) == ["/work/fission"])
    }

    @Test func remoteRelativeQueryUsesMachineProjectAsBase() {
        let projects = RemoteProjectPathResolver.projects(
            matching: "./pa",
            recentPaths: [],
            childNames: ["packages", "apps"],
            relativeBase: "~/src/fission"
        )

        #expect(projects.map(\.path) == ["~/src/fission/packages"])
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
