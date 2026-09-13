import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

struct ProjectPathResolverTests {
    @Test func remotePathQueryFiltersChildDirectories() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "/work",
            namePrefix: "fi",
            listing: .contents(["fission", "notes", "other"])
        )

        #expect(projects.map(\.path) == ["/work/fission"])
        #expect(projects.first?.name == "fission")
    }

    @Test func remoteSlashQueryListsCurrentFolderAndChildren() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "~/src",
            namePrefix: "",
            listing: .contents(["app", "lib"])
        )

        #expect(projects.map(\.path) == ["~/src", "~/src/app", "~/src/lib"])
    }

    @Test func remoteExactPathListsWhatIsInside() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "/work/fission",
            namePrefix: "",
            listing: .contents(["src", "Packages"])
        )

        #expect(projects.map(\.path) == [
            "/work/fission",
            "/work/fission/Packages",
            "/work/fission/src"
        ])
    }

    @Test func remoteMissingOrUnknownPathsCannotBePicked() {
        #expect(
            RemoteProjectPathResolver.projects(
                directory: "/nope",
                namePrefix: "",
                listing: .missing
            ).isEmpty
        )
        #expect(
            RemoteProjectPathResolver.projects(
                directory: "/work",
                namePrefix: "zzz",
                listing: .contents(["fission", "notes"])
            ).isEmpty
        )
        #expect(
            RemoteProjectPathResolver.projects(
                directory: "/work",
                namePrefix: "fi",
                listing: nil
            ).isEmpty
        )
    }

    @Test func remoteHomeListingUsesAvailableDirectories() {
        let projects = RemoteProjectPathResolver.projects(
            directory: "~",
            namePrefix: "s",
            listing: .contents(["src", "work"])
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

        let found = await catalog.listing(on: machine, in: "/work/")
        #expect(found == .contents(["fission", "notes"]))
        let missing = await catalog.listing(on: machine, in: "/nope")
        #expect(missing == .missing)
    }
}
