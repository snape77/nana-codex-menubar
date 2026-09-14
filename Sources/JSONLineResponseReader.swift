import Cocoa
import Foundation

// MARK: - JSON line response reader

final class JSONLineResponseReader {
    private let handle: FileHandle
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var eof = false

    init(handle: FileHandle) {
        self.handle = handle
        self.handle.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let chunk = h.availableData

            self.condition.lock()
            defer {
                self.condition.broadcast()
                self.condition.unlock()
            }

            if chunk.isEmpty {
                self.eof = true
                return
            }

            self.buffer.append(chunk)
            self.consumeLinesLocked()
        }
    }

    deinit {
        stop()
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    func waitForResponse(id: Int, timeout: TimeInterval) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }

        while Date() < deadline {
            if let response = responses.removeValue(forKey: id) {
                return response
            }
            if eof { return nil }
            _ = condition.wait(until: deadline)
        }

        return responses.removeValue(forKey: id)
    }

    private func consumeLinesLocked() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dict = object as? [String: Any],
                  let number = dict["id"] as? NSNumber else {
                continue
            }

            responses[number.intValue] = dict
        }
    }
}
