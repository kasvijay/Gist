import Foundation

/// Thread-safe shared state for audio buffers between Core Audio IO thread and mic callback.
/// Lives outside @MainActor to avoid actor isolation crashes.
final class AudioSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var _systemSamples: [Float] = []
    private var _ready = false

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _ready
    }

    func appendSystemSamples(_ samples: [Float]) {
        lock.lock()
        _systemSamples.append(contentsOf: samples)
        _ready = true
        lock.unlock()
    }

    func consumeSystemSamples(count: Int) -> [Float] {
        lock.lock()
        let available = min(count, _systemSamples.count)
        let result: [Float]
        if available > 0 {
            result = Array(_systemSamples.prefix(available))
            _systemSamples.removeFirst(available)
        } else {
            result = []
        }
        lock.unlock()
        return result
    }

    private var _callbackCount = 0
    private var _writerStarted = false

    /// Atomically check whether the writer should be skipped this callback.
    /// Returns true if the writer is not yet ready (skip writing this buffer).
    /// Returns false if the writer is already started or has just been started.
    func shouldSkipWriter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _writerStarted { return false }
        _callbackCount += 1
        if !_ready && _callbackCount < 10 {
            return true
        }
        _writerStarted = true
        return false
    }

    func reset() {
        lock.lock()
        _systemSamples = []
        _ready = false
        _callbackCount = 0
        _writerStarted = false
        lock.unlock()
    }
}
