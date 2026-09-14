import Cocoa
import Foundation

// MARK: - Codex quota reader

final class CodexQuotaReader {
    private struct RateCandidate {
        let path: String
        let durationMinutes: Int
        let usedPercent: Double
        let resetsAt: Date?
    }

    enum ReaderError: Error {
        case codexNotFound
        case launchFailed
        case initializationTimeout
        case rateLimitTimeout
        case malformedResponse
    }

    func fetch() throws -> QuotaSnapshot {
        guard let binary = findCodexBinary() else {
            throw ReaderError.codexNotFound
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server", "--listen", "stdio://"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { h in
            _ = h.availableData
        }

        let reader = JSONLineResponseReader(handle: outputPipe.fileHandleForReading)

        defer {
            reader.stop()
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? inputPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        do {
            try process.run()
        } catch {
            throw ReaderError.launchFailed
        }

        try send([
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "nana-menubar",
                    "title": "nana Codex menu bar",
                    "version": "1.0.0"
                ]
            ]
        ], to: inputPipe.fileHandleForWriting)

        guard reader.waitForResponse(id: 1, timeout: 6.0) != nil else {
            throw ReaderError.initializationTimeout
        }

        try send(["method": "initialized"], to: inputPipe.fileHandleForWriting)
        try send(["method": "account/rateLimits/read", "id": 2], to: inputPipe.fileHandleForWriting)

        guard let response = reader.waitForResponse(id: 2, timeout: 8.0),
              let result = response["result"] as? [String: Any] else {
            throw ReaderError.rateLimitTimeout
        }

        let candidates = collectRateWindows(from: result)
        let five = pickWindow(duration: 300, from: candidates)
        let week = pickWindow(duration: 10_080, from: candidates)

        if five == nil && week == nil {
            throw ReaderError.malformedResponse
        }

        return QuotaSnapshot(
            fiveHour: five.map {
                QuotaWindow(remainingPercent: clamp(100.0 - $0.usedPercent), resetsAt: $0.resetsAt)
            },
            weekly: week.map {
                QuotaWindow(remainingPercent: clamp(100.0 - $0.usedPercent), resetsAt: $0.resetsAt)
            }
        )
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func collectRateWindows(from root: Any) -> [RateCandidate] {
        var output: [RateCandidate] = []

        func walk(_ value: Any, path: String) {
            if let dict = value as? [String: Any] {
                if let duration = number(dict["windowDurationMins"])?.intValue,
                   let used = number(dict["usedPercent"])?.doubleValue {
                    let resetDate: Date?
                    if let ts = number(dict["resetsAt"])?.doubleValue {
                        resetDate = Date(timeIntervalSince1970: ts)
                    } else {
                        resetDate = nil
                    }
                    output.append(RateCandidate(path: path.lowercased(), durationMinutes: duration, usedPercent: used, resetsAt: resetDate))
                }

                for (key, child) in dict {
                    walk(child, path: path.isEmpty ? key : "\(path).\(key)")
                }
            } else if let array = value as? [Any] {
                for (index, child) in array.enumerated() {
                    walk(child, path: "\(path)[\(index)]")
                }
            }
        }

        walk(root, path: "result")
        return output
    }

    private func pickWindow(duration: Int, from candidates: [RateCandidate]) -> RateCandidate? {
        let matches = candidates.filter { $0.durationMinutes == duration }
        if matches.isEmpty { return nil }

        if let canonical = matches.first(where: { $0.path.contains("ratelimitsbylimitid.codex") }) {
            return canonical
        }

        if let root = matches.first(where: {
            $0.path.contains(".ratelimits.") && !$0.path.contains("ratelimitsbylimitid")
        }) {
            return root
        }

        return nil
    }

    private func number(_ value: Any?) -> NSNumber? {
        if let n = value as? NSNumber { return n }
        if let s = value as? String, let d = Double(s) { return NSNumber(value: d) }
        return nil
    }

    private func clamp(_ value: Double) -> Double {
        min(100.0, max(0.0, value))
    }

    private func findCodexBinary() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser.path

        var candidates: [String] = []

        if let explicit = env["CODEX_BIN"], !explicit.isEmpty {
            candidates.append((explicit as NSString).expandingTildeInPath)
        }

        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.volta/bin/codex"
        ]

        if let path = env["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append("\(dir)/codex")
            }
        }

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
