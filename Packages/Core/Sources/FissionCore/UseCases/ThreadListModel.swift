import Foundation
import Observation

/// Shared observable state and behavior for presenting Threads.
@MainActor
@Observable
public final class ThreadListModel {
    public private(set) var threads: [AgentThread] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let databasePath: String
    private var repository: SQLiteThreadRepository?
    private var didLoad = false

    public static var applicationSupportDatabasePath: String {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "fission.sqlite").path
    }

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public func load() async {
        guard !didLoad, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let repository = try repository ?? SQLiteThreadRepository(path: databasePath)
            self.repository = repository

            if try await repository.list().isEmpty {
                try await repository.create(AgentThread(title: "Explore Fission"))
            }

            try await refresh(using: repository)
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func createThread(
        id: UUID = UUID(),
        title: String,
        workingDirectory: String? = nil
    ) async -> UUID? {
        guard let repository, didLoad else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let thread = AgentThread(
            id: id,
            title: trimmedTitle,
            workingDirectory: workingDirectory
        )

        do {
            try await repository.create(thread)
            try await refresh(using: repository)
            return thread.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func settle(threadID: UUID) async {
        await transition(threadID: threadID, to: .settled)
    }

    public func reopen(threadID: UUID) async {
        await transition(threadID: threadID, to: .active)
    }

    public func deleteThreads(ids: [UUID]) async {
        guard let repository, didLoad else { return }

        do {
            for id in ids {
                try await repository.delete(id: id)
            }
            try await refresh(using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transition(threadID: UUID, to status: AgentThread.Status) async {
        guard let repository,
              didLoad,
              var thread = threads.first(where: { $0.id == threadID }) else {
            return
        }

        thread.transition(to: status)

        do {
            try await repository.update(thread)
            try await refresh(using: repository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh(using repository: SQLiteThreadRepository) async throws {
        threads = try await repository.list()
        errorMessage = nil
    }
}
