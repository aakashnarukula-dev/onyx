import Foundation
import OnyxCore

// onyx-pane: lets Claude sessions in Onyx panes see each other and push safely.
// First token of every output line is machine-readable (OK, USE_WORKTREE, PUSHED, CONFLICT, NO_REMOTE, RELEASED, ERROR).

let usage = """
usage: onyx-pane claim <dir> "<task>"   register this pane in a repo (may assign a worktree)
       onyx-pane who [<dir>]            list panes working in the repo
       onyx-pane push [<dir>]           rebase onto the latest remote and push (one pane at a time)
       onyx-pane release [<dir>]        drop this pane's claim; remove its worktree once merged
"""

func fail(_ msg: String, _ code: Int32 = 3) -> Never {
    print("ERROR \(msg)")
    exit(code)
}

let env = ProcessInfo.processInfo.environment
var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(64) }
args.removeFirst()
if cmd == "-h" || cmd == "--help" || cmd == "help" { print(usage); exit(0) }
guard let paneId = env["ONYX_PANE_ID"], !paneId.isEmpty else { fail("not in an Onyx pane") }

let paths = OnyxPaths(env: env)
let commands = PaneCommands(paneId: paneId, registry: PaneRegistry(paths: paths), paths: paths)
let cwd = FileManager.default.currentDirectoryPath

do {
    switch cmd {
    case "claim":
        guard args.count >= 2 else { fail("usage: onyx-pane claim <dir> \"<task>\"") }
        print(try commands.claim(dir: args[0], task: args.dropFirst().joined(separator: " ")))
    case "who":
        let out = try commands.who(dir: args.first ?? cwd)
        print(out.isEmpty ? "(no panes)" : out)
    case "push":
        let r = try commands.push(dir: args.first ?? cwd)
        print(r.output)
        exit(r.exitCode)
    case "release":
        print(try commands.release(dir: args.first ?? cwd))
    default:
        print(usage)
        exit(64)
    }
} catch OnyxError.lockTimeout {
    fail("timed out waiting for another pane's push")
} catch OnyxError.notARepo(let dir) {
    fail("not a git repository: \(dir)")
} catch OnyxError.git(let msg) {
    fail(msg.replacingOccurrences(of: "\n", with: " | "))
} catch {
    fail("\(error)")
}
