import Foundation
import GRDB

private struct ThreadRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "threads"
    static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.timeIntervalSince1970
    static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.timeIntervalSince1970

    var id: String
    var title: String
    var status: String
    var workingDirectory: String?
    var projectName: String?
    var remoteMachineID: String?
    var remoteCommand: String?
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case workingDirectory = "working_directory"
        case projectName = "project_name"
        case remoteMachineID = "remote_machine_id"
        case remoteCommand = "remote_command"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sortIndex = "sort_index"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let sortIndex = Column(CodingKeys.sortIndex)
    }

    init(_ thread: AgentThread) {
        id = thread.id.uuidString
        title = thread.title
        status = thread.status.rawValue
        workingDirectory = thread.workingDirectory
        projectName = thread.projectName
        remoteMachineID = thread.remoteMachineID?.uuidString
        remoteCommand = thread.remoteCommand
        createdAt = thread.createdAt
        updatedAt = thread.updatedAt
        sortIndex = thread.sortIndex
    }

    func thread() throws -> AgentThread {
        guard let id = UUID(uuidString: id),
              let status = AgentThread.Status(rawValue: status) else {
            throw SQLiteRepositoryError.invalidStoredThread
        }

        let remoteMachineID = remoteMachineID.flatMap(UUID.init(uuidString:))
        return AgentThread(
            id: id,
            title: title,
            status: status,
            workingDirectory: workingDirectory,
            projectName: projectName,
            remoteMachineID: remoteMachineID,
            remoteCommand: remoteCommand,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortIndex: sortIndex
        )
    }
}

/// A SQLite-backed Thread repository. GRDB serializes access through its database queue.
public actor SQLiteThreadRepository {
    private let database: DatabaseQueue

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)

        do {
            database = try DatabaseQueue(path: path, configuration: configuration)
        } catch {
            throw SQLiteRepositoryError.cannotOpenDatabase(String(describing: error))
        }

        do {
            try Self.makeMigrator().migrate(database)
        } catch {
            throw Self.queryError(error)
        }
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerCreateThreadsMigration(in: &migrator)
        registerWorkingDirectoryMigration(in: &migrator)
        registerSettledStatusMigration(in: &migrator)
        registerProjectNameMigration(in: &migrator)
        registerSortIndexMigration(in: &migrator)
        registerRemoteThreadMigration(in: &migrator)
        return migrator
    }

    private static func registerCreateThreadsMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createThreads") { db in
            try db.create(table: ThreadRecord.databaseTableName, ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("status", .text)
                    .notNull()
                    .check { ["active", "completed", "failed", "cancelled"].contains($0) }
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(
                index: "threads_updated_at",
                on: ThreadRecord.databaseTableName,
                columns: ["updated_at"],
                ifNotExists: true
            )
        }
    }

    private static func registerWorkingDirectoryMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addThreadWorkingDirectory") { db in
            try db.alter(table: ThreadRecord.databaseTableName) { table in
                table.add(column: "working_directory", .text)
            }
        }
    }

    private static func registerSettledStatusMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addSettledThreadStatus") { db in
            try db.create(table: "threads_with_settled_status") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("status", .text)
                    .notNull()
                    .check {
                        ["active", "settled", "completed", "failed", "cancelled"].contains($0)
                    }
                table.column("working_directory", .text)
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.execute(
                sql: """
                    INSERT INTO threads_with_settled_status
                        (id, title, status, working_directory, created_at, updated_at)
                    SELECT id, title, status, working_directory, created_at, updated_at
                    FROM threads
                    """
            )
            try db.drop(table: ThreadRecord.databaseTableName)
            try db.rename(table: "threads_with_settled_status", to: ThreadRecord.databaseTableName)
            try db.create(
                index: "threads_updated_at",
                on: ThreadRecord.databaseTableName,
                columns: ["updated_at"]
            )
        }
    }

    private static func registerProjectNameMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addThreadProjectName") { db in
            try db.alter(table: ThreadRecord.databaseTableName) { table in
                table.add(column: "project_name", .text)
            }
        }
    }

    private static func registerSortIndexMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addThreadSortIndex") { db in
            try db.alter(table: ThreadRecord.databaseTableName) { table in
                table.add(column: "sort_index", .integer).notNull().defaults(to: 0)
            }
            try db.execute(
                sql: """
                    UPDATE threads SET sort_index = (
                        SELECT COUNT(*) FROM threads AS other
                        WHERE other.updated_at > threads.updated_at
                           OR (
                                other.updated_at = threads.updated_at
                                AND other.id < threads.id
                           )
                    )
                    """
            )
        }
    }

    private static func registerRemoteThreadMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addThreadRemoteMachine") { db in
            try db.alter(table: ThreadRecord.databaseTableName) { table in
                table.add(column: "remote_machine_id", .text)
                table.add(column: "remote_command", .text)
            }
        }
    }

    public func create(_ thread: AgentThread) async throws {
        do {
            try await database.write { db in
                var record = ThreadRecord(thread)
                let existingCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM threads"
                ) ?? 0
                if existingCount == 0 {
                    record.sortIndex = 0
                } else {
                    let minimum = try Int.fetchOne(
                        db,
                        sql: "SELECT MIN(sort_index) FROM threads"
                    ) ?? 0
                    record.sortIndex = minimum - 1
                }
                try record.insert(db)
            }
        } catch DatabaseError.SQLITE_CONSTRAINT {
            throw SQLiteRepositoryError.threadAlreadyExists
        } catch {
            throw Self.queryError(error)
        }
    }

    public func thread(id: UUID) async throws -> AgentThread? {
        do {
            return try await database.read { db in
                try ThreadRecord.fetchOne(db, key: id.uuidString)?.thread()
            }
        } catch let error as SQLiteRepositoryError {
            throw error
        } catch {
            throw Self.queryError(error)
        }
    }

    public func list() async throws -> [AgentThread] {
        do {
            return try await database.read { db in
                try ThreadRecord
                    .order(
                        ThreadRecord.Columns.sortIndex,
                        ThreadRecord.Columns.updatedAt.desc,
                        ThreadRecord.Columns.id
                    )
                    .fetchAll(db)
                    .map { try $0.thread() }
            }
        } catch let error as SQLiteRepositoryError {
            throw error
        } catch {
            throw Self.queryError(error)
        }
    }

    public func reorder(ids: [UUID]) async throws {
        do {
            try await database.write { db in
                for (index, id) in ids.enumerated() {
                    let updated = try ThreadRecord
                        .filter(ThreadRecord.Columns.id == id.uuidString)
                        .updateAll(db, ThreadRecord.Columns.sortIndex.set(to: index))
                    guard updated == 1 else {
                        throw SQLiteRepositoryError.threadNotFound
                    }
                }
            }
        } catch let error as SQLiteRepositoryError {
            throw error
        } catch {
            throw Self.queryError(error)
        }
    }

    public func update(_ thread: AgentThread) async throws {
        do {
            try await database.write { db in
                try ThreadRecord(thread).update(db)
            }
        } catch RecordError.recordNotFound {
            throw SQLiteRepositoryError.threadNotFound
        } catch {
            throw Self.queryError(error)
        }
    }

    public func delete(id: UUID) async throws {
        do {
            let deleted = try await database.write { db in
                try ThreadRecord.deleteOne(db, key: id.uuidString)
            }
            guard deleted else {
                throw SQLiteRepositoryError.threadNotFound
            }
        } catch let error as SQLiteRepositoryError {
            throw error
        } catch {
            throw Self.queryError(error)
        }
    }

    private static func queryError(_ error: Error) -> SQLiteRepositoryError {
        .queryFailed(String(describing: error))
    }
}
