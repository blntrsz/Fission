public enum SQLiteRepositoryError: Error, Equatable, Sendable {
    case cannotOpenDatabase(String)
    case queryFailed(String)
    case invalidStoredThread
    case threadAlreadyExists
    case threadNotFound
}
