import Cocoa
import Foundation

// MARK: - Current model reader

final class CodexModelReader {
    private let fm = FileManager.default
    private var cachedRollout: URL?
    private var scanCounter = 0

    func currentModel() -> ModelSnapshot {
        scanCounter += 1
        if cachedRollout == nil || scanCounter >= 5 {
            cachedRollout = newestRootRollout()
            scanCounter = 0
        }
        if let rollout = cachedRollout,
           let snapshot = readTurnContext(from: rollout) {
            return snapshot
        }
        return readConfigFallback()
    }

    private func newestRootRollout() -> URL? {
        let root = codexHome().appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var bestURL: URL?
        var bestDate = Date.distantPast

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate,
                  date > bestDate else { continue }
            if isRootRollout(url) {
                bestURL = url
                bestDate = date
            }
        }
        return bestURL
    }

    private func isRootRollout(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 96 * 1024)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return true }

        for line in text.split(separator: "\n").prefix(16) {
            guard let d = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  (obj["type"] as? String) == "session_meta",
                  let payload = obj["payload"] as? [String: Any] else { continue }
            if let parent = payload["parent_thread_id"], !(parent is NSNull) { return false }
            return true
        }
        return true
    }

    private func readTurnContext(from url: URL) -> ModelSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end: UInt64
        do { end = try handle.seekToEnd() } catch { return nil }
        let maxBytes: UInt64 = 2 * 1024 * 1024
        let start = end > maxBytes ? end - maxBytes : 0
        do { try handle.seek(toOffset: start) } catch { return nil }
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let lineData = String(rawLine).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "turn_context",
                  let payload = obj["payload"] as? [String: Any] else { continue }

            let model = payload["model"] as? String
            var effort = payload["effort"] as? String
            if effort == nil,
               let collaboration = payload["collaboration_mode"] as? [String: Any],
               let settings = collaboration["settings"] as? [String: Any] {
                effort = settings["reasoning_effort"] as? String
            }
            if model != nil || effort != nil {
                return ModelSnapshot(model: model, effort: effort)
            }
        }
        return nil
    }

    private func readConfigFallback() -> ModelSnapshot {
        let config = codexHome().appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else {
            return ModelSnapshot(model: nil, effort: nil)
        }

        var model: String?
        var effort: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("model =") && model == nil {
                model = quotedValue(in: line)
            } else if line.hasPrefix("model_reasoning_effort =") && effort == nil {
                effort = quotedValue(in: line)
            }
            if model != nil && effort != nil { break }
        }
        return ModelSnapshot(model: model, effort: effort)
    }

    private func quotedValue(in line: String) -> String? {
        guard let first = line.firstIndex(of: "\"") else { return nil }
        let rest = line[line.index(after: first)...]
        guard let second = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<second])
    }

    private func codexHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
}
