import Foundation

/// Thread-safe text accumulator for streaming LLM responses.
final class StreamAccumulator: @unchecked Sendable {
    private var text = ""
    private let lock = NSLock()

    func append(_ string: String) {
        lock.lock()
        text += string
        lock.unlock()
    }

    func set(_ string: String) {
        lock.lock()
        text = string
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
