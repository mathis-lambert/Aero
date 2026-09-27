/// Actionable storage failures. SQL text, URLs and user contents never enter these errors.
public enum StorageError: Error, Equatable, Sendable {
    case inUse, newerVersion, invalidData, foreignDatabase
    case sqlite(Int32)
}
