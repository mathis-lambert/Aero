import Darwin
import Foundation

/// Process lifetime lock. The file remains; the OS releases the lock after a crash.
final class StorageLock {
    private let descriptor: Int32
    init(directory: URL) throws {
        let file = directory.appendingPathComponent(".writer-lock")
        let descriptor = Darwin.open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw StorageError.inUse
        }
        self.descriptor = descriptor
    }
    deinit { Darwin.close(descriptor) }
}
