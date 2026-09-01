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

    func createThread(title: String, workingDirectory: String) async -> UUID? {
        guard let repository else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let thread = AgentThread(
            title: trimmedTitle,
            workingDirectory: workingDirectory
        )
        do {
            try await repository.create(thread)
            threads = try await repository.list()
            return thread.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func settle(threadID: UUID) async {
        await transition(threadID: threadID, to: .settled)
    }

    func reopen(threadID: UUID) async {
        await transition(threadID: threadID, to: .active)
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

    private func transition(threadID: UUID, to status: AgentThread.Status) async {
        guard let repository,
              var thread = threads.first(where: { $0.id == threadID }) else {
            return
        }

        thread.transition(to: status)
        do {
            try await repository.update(thread)
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
