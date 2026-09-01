import FissionCore
import Foundation
import Observation

@MainActor
@Observable
final class ThreadListViewModel {
    private(set) var threads: [AgentThread] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var repository: SQLiteThreadRepository?

    func load() async {
        guard repository == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = try SQLiteThreadRepository(path: Self.databaseURL.path)
            self.repository = repository

            if try await repository.list().isEmpty {
                try await repository.create(
                    AgentThread(title: "Explore Fission")
                )
            }
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createThread(title: String) async {
        guard let repository else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            try await repository.create(AgentThread(title: trimmedTitle))
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteThreads(ids: [UUID]) async {
        guard let repository else { return }

        do {
            for id in ids {
                try await repository.delete(id: id)
            }
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var databaseURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "fission.sqlite")
    }
}
