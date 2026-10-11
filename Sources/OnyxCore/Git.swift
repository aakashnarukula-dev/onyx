import Foundation

public struct GitResult: Sendable {
    public let status: Int32
    public let out: String
    public let err: String
}

public enum Git {
    /// Runs git in `dir`; never prompts for credentials.
    public static func result(_ args: [String], in dir: String) -> GitResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return GitResult(status: -1, out: "", err: "\(error)") }
        // Read both pipes concurrently so a chatty stderr cannot block the child.
        nonisolated(unsafe) var errData = Data()
        let reader = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
        reader.start()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        while !reader.isFinished { usleep(1000) }
        let trim = { (d: Data) in String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        return GitResult(status: p.terminationStatus, out: trim(outData), err: trim(errData))
    }

    /// Runs git and returns stdout; throws `OnyxError.git` with stderr on failure.
    @discardableResult
    public static func run(_ args: [String], in dir: String) throws -> String {
        let r = result(args, in: dir)
        guard r.status == 0 else { throw OnyxError.git(r.err.isEmpty ? r.out : r.err) }
        return r.out
    }
}
