import Foundation

public enum Shell {
    /// Runs an executable and captures its output. Never throws; failure to launch is status -1.
    public static func run(_ path: String, _ args: [String], env: [String: String]? = nil) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env { p.environment = env }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "", "\(error)") }
        nonisolated(unsafe) var errData = Data()
        let reader = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
        reader.start()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        while !reader.isFinished { usleep(1000) }
        return (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }

    /// Finds a CLI tool. Apps launched from Finder get a bare PATH, so Homebrew dirs are checked too.
    public static func which(_ name: String, path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String {
        let dirs = (path ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", "/usr/bin", "/bin"]
        for d in dirs where FileManager.default.isExecutableFile(atPath: d + "/" + name) {
            return d + "/" + name
        }
        return "/usr/bin/env"
    }
}
