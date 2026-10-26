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
        // Scan disjoint outer objects once. Never retry nested suffixes or
        // retain candidate copies; quoted braces are data, including in logs.
        var start: Data.Index?
        var depth = 0
        var inString = false
        var escaped = false
        for index in data.indices {
            let byte = data[index]
            // Log quotes cannot span lines; JSON candidate state must.
            if depth == 0, byte == 0x0A || byte == 0x0D {
                inString = false
                escaped = false
                continue
            }
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { inString = false }
                continue
            }
            if byte == 0x22 { inString = true; continue }
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
        }
        return nil
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
