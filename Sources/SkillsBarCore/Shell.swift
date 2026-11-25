import Foundation

public struct CommandResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String { stdout + "\n" + stderr }
    public var shortFailure: String { String((stderr.isEmpty ? stdout : stderr).prefix(110)).replacingOccurrences(of: "\n", with: " ") }
    public var json: JSONNode? {
        let data = Data(stdout.utf8)
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return JSONNode(object)
        }

        func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        // Recovery candidates are scanned once. The first non-whitespace byte
        // after an opening brace must be a JSON object key or the empty-object
        // close; other braces are treated as diagnostic text.
        func recoverObjectStarting(at start: Data.Index) -> (end: Data.Index, node: JSONNode?, validPrefix: Bool) {
            var depth = 1
            var arrayDepth = 0
            var candidateInString = false
            var candidateEscaped = false
            var awaitingFirstMember = true
            var lastSignificantByte: UInt8 = 0x7B
            var nestedCandidateStart: Data.Index?
            var lastCompleteNestedNode: JSONNode?
            var lastCompleteNestedEnd: Data.Index?
            var index = data.index(after: start)
            while index < data.endIndex {
                let byte = data[index]
                // A quoted log ends at a line boundary. Let the outer scanner
                // resume on the next line instead of swallowing its JSON.
                if byte == 0x0A || byte == 0x0D {
                    let nestedFallback: JSONNode? = lastCompleteNestedNode.flatMap { node -> JSONNode? in
                        guard let nestedEnd = lastCompleteNestedEnd else { return nil }
                        var suffix = nestedEnd
                        while suffix < index {
                            if !isWhitespace(data[suffix]) { return nil }
                            suffix = data.index(after: suffix)
                        }
                        return node
                    }
                    return (index, nestedFallback, true)
                }
                if awaitingFirstMember {
                    if isWhitespace(byte) {
                        index = data.index(after: index)
                        continue
                    }
                    if byte == 0x22 {
                        awaitingFirstMember = false
                        candidateInString = true
                        index = data.index(after: index)
                        continue
                    }
                    if byte == 0x7D {
                        let end = data.index(after: index)
                        let candidate = data.subdata(in: start..<end)
                        let node = (try? JSONSerialization.jsonObject(with: candidate)).map(JSONNode.init)
                        return (end, node, true)
                    }
                    return (data.index(after: start), nil, false)
                }
                if candidateInString {
                    if candidateEscaped { candidateEscaped = false }
                    else if byte == 0x5C { candidateEscaped = true }
                    else if byte == 0x22 {
                        candidateInString = false
                        lastSignificantByte = byte
                    }
                } else if byte == 0x22 {
                    guard lastSignificantByte == 0x7B || lastSignificantByte == 0x2C || lastSignificantByte == 0x3A || lastSignificantByte == 0x5B else {
                        return (data.index(after: index), nil, false)
                    }
                    candidateInString = true
                } else if byte == 0x5B {
                    arrayDepth += 1
                    lastSignificantByte = byte
                } else if byte == 0x5D {
                    arrayDepth = max(0, arrayDepth - 1)
                    lastSignificantByte = byte
                } else if byte == 0x7B {
                    if depth == 1, arrayDepth == 0 { nestedCandidateStart = index }
                    depth += 1
                    lastSignificantByte = byte
                } else if byte == 0x7D, depth > 0 {
                    depth -= 1
                    if depth == 1, let nestedStart = nestedCandidateStart {
                        let nestedEnd = data.index(after: index)
                        let nestedCandidate = data.subdata(in: nestedStart..<nestedEnd)
                        if let object = try? JSONSerialization.jsonObject(with: nestedCandidate) {
                            lastCompleteNestedNode = JSONNode(object)
                            lastCompleteNestedEnd = nestedEnd
                        }
                        nestedCandidateStart = nil
                    }
                    if depth == 0 {
                        let end = data.index(after: index)
                        let candidate = data.subdata(in: start..<end)
                        let node = (try? JSONSerialization.jsonObject(with: candidate)).map(JSONNode.init)
                        return (end, node, true)
                    }
                    lastSignificantByte = byte
                } else if !isWhitespace(byte) {
                    lastSignificantByte = byte
                }
                index = data.index(after: index)
            }
            let nestedFallback: JSONNode? = lastCompleteNestedNode.flatMap { node -> JSONNode? in
                guard let nestedEnd = lastCompleteNestedEnd else { return nil }
                var suffix = nestedEnd
                while suffix < data.endIndex {
                    if !isWhitespace(data[suffix]) { return nil }
                    suffix = data.index(after: suffix)
                }
                return node
            }
            return (data.endIndex, nestedFallback, true)
        }

        // A malformed brace inside a quoted diagnostic can contain nested
        // braces. Skip that complete span so its inner objects cannot become
        // recovery candidates. A quote closes the log text unless it appears
        // where a JSON key or value string can begin.
        func skipMalformedQuotedBrace(at start: Data.Index) -> (end: Data.Index, quoteClosed: Bool) {
            var depth = 1
            var inNestedString = false
            var nestedEscaped = false
            var logEscaped = false
            var lastSignificantByte: UInt8 = 0x7B
            var index = data.index(after: start)
            while index < data.endIndex {
                let byte = data[index]
                if byte == 0x0A || byte == 0x0D { return (index, false) }
                if inNestedString {
                    if nestedEscaped { nestedEscaped = false }
                    else if byte == 0x5C { nestedEscaped = true }
                    else if byte == 0x22 {
                        inNestedString = false
                        lastSignificantByte = byte
                    }
                    index = data.index(after: index)
                    continue
                }
                if logEscaped {
                    logEscaped = false
                    if byte == 0x22 || byte == 0x5C {
                        lastSignificantByte = byte
                        index = data.index(after: index)
                        continue
                    }
                }
                if byte == 0x5C {
                    logEscaped = true
                    index = data.index(after: index)
                    continue
                }
                if byte == 0x22 {
                    if lastSignificantByte == 0x7B || lastSignificantByte == 0x2C || lastSignificantByte == 0x3A || lastSignificantByte == 0x5B {
                        inNestedString = true
                        nestedEscaped = false
                        lastSignificantByte = byte
                    } else {
                        return (data.index(after: index), true)
                    }
                } else if byte == 0x7B {
                    depth += 1
                    lastSignificantByte = byte
                } else if byte == 0x7D {
                    depth -= 1
                    lastSignificantByte = byte
                    if depth == 0 { return (data.index(after: index), false) }
                } else if !isWhitespace(byte) {
                    lastSignificantByte = byte
                }
                index = data.index(after: index)
            }
            return (data.endIndex, false)
        }

        // Scan disjoint outer objects once. A recovered object remains pending
        // until the enclosing log quote closes or the line ends. This avoids
        // rescanning every remaining brace suffix in quoted output.
        var start: Data.Index?
        var depth = 0
        var inString = false
        var escaped = false
        var pendingRecovered: JSONNode?
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            // Log quotes cannot span lines; JSON candidate state must.
            if depth == 0, byte == 0x0A || byte == 0x0D {
                if let pendingRecovered { return pendingRecovered }
                inString = false
                escaped = false
                index = data.index(after: index)
                continue
            }
            if depth == 0, inString, !escaped, byte == 0x7B {
                let recovered = recoverObjectStarting(at: index)
                if recovered.validPrefix {
                    if pendingRecovered == nil { pendingRecovered = recovered.node }
                    index = recovered.end
                    continue
                }
                let skipped = skipMalformedQuotedBrace(at: index)
                if skipped.quoteClosed {
                    inString = false
                    escaped = false
                    pendingRecovered = nil
                }
                index = skipped.end
                continue
            }
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 {
                    inString = false
                    pendingRecovered = nil
                }
                index = data.index(after: index)
                continue
            }
            if byte == 0x22 { inString = true; index = data.index(after: index); continue }
            if byte == 0x7B {
                if depth == 0 { start = index }
                depth += 1
            } else if byte == 0x7D, depth > 0 {
                depth -= 1
                if depth == 0, let candidateStart = start {
                    let candidate = data.subdata(in: candidateStart..<(index + 1))
                    if let object = try? JSONSerialization.jsonObject(with: candidate) {
                        return JSONNode(object)
                    }
                    start = nil
                }
            }
            index = data.index(after: index)
        }
        return pendingRecovered
    }
}

public enum Shell {
    /// Returns a deterministic tool path for read-only Skills SDK checks.
    ///
    /// SkillsBar launches commands from a non-login shell, but the inherited
    /// environment can still put mise shims ahead of the real tools. That
    /// makes the same SDK command behave differently in the app than it does
    /// in a developer terminal (for example when mise's global config is not
    /// trusted). Keep the user's usable paths while removing mise entries and
    /// appending the known local/system tool locations exactly once.
    internal static func sanitizedPath(_ existingPath: String, localBin: String) -> String {
        let inheritedEntries = existingPath
            .split(separator: ":")
            .map(String.init)
            .filter { entry in
                !entry.split(separator: "/").contains("mise")
            }
        let requiredEntries = [
            localBin,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        var seen = Set<String>()
        return (requiredEntries + inheritedEntries).filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    public static func run(_ command: String, cwd: URL, timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", command]
        process.currentDirectoryURL = cwd
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin")
            .path
        let managedPython = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".venvs/pyyaml/bin/python")
        var overrides = [
            "PATH": sanitizedPath(existingPath, localBin: localBin),
            "ZDOTDIR": "/private/tmp/skillsbar-zdotdir",
            "MISE_CONFIG_FILE": "/dev/null",
            "MISE_NO_CONFIG": "1",
            "MISE_NO_ENV": "1",
            "MISE_NO_HOOKS": "1",
            "XDG_CACHE_HOME": "/private/tmp/skillsbar-xdg",
            "MISE_CACHE_DIR": "/private/tmp/skillsbar-mise-cache",
            "MISE_OFFLINE": "1",
            "MISE_JOBS": "2",
            "UV_CACHE_DIR": "/private/tmp/skillsbar-uv-cache",
            "UV_OFFLINE": "1",
            "npm_config_offline": "true"
        ]
        for path in [
            overrides["ZDOTDIR"],
            overrides["XDG_CACHE_HOME"],
            overrides["MISE_CACHE_DIR"],
            overrides["UV_CACHE_DIR"]
        ].compactMap({ $0 }) {
            do {
                try FileManager.default.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: true
                )
            } catch {
                return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
            }
        }
        if FileManager.default.isExecutableFile(atPath: managedPython.path) {
            overrides["PYTHON_BIN"] = managedPython.path
        }
        process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        let outputGroup = DispatchGroup()
        let stdoutData = LockedData()
        let stderrData = LockedData()
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData.set(stdoutHandle.readDataToEndOfFile())
            outputGroup.leave()
        }
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData.set(stderrHandle.readDataToEndOfFile())
            outputGroup.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        outputGroup.wait()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData.value, encoding: .utf8) ?? "",
            stderr: String(data: stderrData.value, encoding: .utf8) ?? ""
        )
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }
}

public struct JSONNode {
    public var value: Any
    public init(_ value: Any) { self.value = value }

    public func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = findValue(named: key, in: value) as? String { return value }
        }
        return nil
    }

    public func firstInt(for keys: [String]) -> Int? {
        for key in keys {
            if let int = findValue(named: key, in: value) as? Int { return int }
            if let double = findValue(named: key, in: value) as? Double,
               let int = Int(exactly: double) { return int }
        }
        return nil
    }

    public func firstDouble(for keys: [String]) -> Double? {
        for key in keys {
            if let double = findValue(named: key, in: value) as? Double { return double }
            if let int = findValue(named: key, in: value) as? Int { return Double(int) }
        }
        return nil
    }

    public func firstBool(for keys: [String]) -> Bool? {
        for key in keys {
            if let bool = findValue(named: key, in: value) as? Bool { return bool }
        }
        return nil
    }

    public func allStrings(for key: String) -> [String] {
        var results: [String] = []
        collectStrings(named: key, from: value, into: &results)
        return results
    }

    public func string(at path: [String]) -> String? {
        value(at: path) as? String
    }

    public func int(at path: [String]) -> Int? {
        if let int = value(at: path) as? Int { return int }
        if let double = value(at: path) as? Double,
           let int = Int(exactly: double) { return int }
        return nil
    }

    public func bool(at path: [String]) -> Bool? {
        value(at: path) as? Bool
    }

    public func stringArray(at path: [String]) -> [String] {
        value(at: path) as? [String] ?? []
    }

    public func arrayOfDictionaries(at path: [String]) -> [[String: Any]] {
        value(at: path) as? [[String: Any]] ?? []
    }

    private func value(at path: [String]) -> Any? {
        var current: Any? = value
        for key in path {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[key]
        }
        return current
    }

    private func findValue(named key: String, in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] { return value }
            for value in dictionary.values {
                if let found = findValue(named: key, in: value) { return found }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let found = findValue(named: key, in: value) { return found }
            }
        }
        return nil
    }

    private func collectStrings(named key: String, from object: Any, into results: inout [String]) {
        if let dictionary = object as? [String: Any] {
            if let values = dictionary[key] as? [String] { results.append(contentsOf: values) }
            if let value = dictionary[key] as? String { results.append(value) }
            for value in dictionary.values { collectStrings(named: key, from: value, into: &results) }
        }
        if let array = object as? [Any] {
            for value in array { collectStrings(named: key, from: value, into: &results) }
        }
    }
}
