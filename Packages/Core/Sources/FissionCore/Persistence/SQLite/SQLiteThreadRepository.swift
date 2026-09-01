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
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case workingDirectory = "working_directory"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(_ thread: AgentThread) {
        id = thread.id.uuidString
        title = thread.title
        status = thread.status.rawValue
        workingDirectory = thread.workingDirectory
        createdAt = thread.createdAt
        updatedAt = thread.updatedAt
    }

    func thread() throws -> AgentThread {
        guard let id = UUID(uuidString: id),
              let status = AgentThread.Status(rawValue: status) else {
            throw SQLiteRepositoryError.invalidStoredThread
        }

        return AgentThread(
            id: id,
            title: title,
            status: status,
            workingDirectory: workingDirectory,
            createdAt: createdAt,
            updatedAt: updatedAt
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

    public func create(_ thread: AgentThread) async throws {
        do {
            try await database.write { db in
                try ThreadRecord(thread).insert(db)
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
                    .order(ThreadRecord.Columns.updatedAt.desc, ThreadRecord.Columns.id)
                    .fetchAll(db)
                    .map { try $0.thread() }
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
