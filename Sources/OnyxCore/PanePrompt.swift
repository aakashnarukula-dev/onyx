import Foundation

/// Appended to the system prompt of every Claude session an Onyx pane starts.
public enum PanePrompt {
    public static let text = """
    You are running in an Onyx terminal pane. Other panes may be working in the same repositories.

    Follow these rules whenever you work in a git repository:

    1. Before editing any file in a git repo, run `onyx-pane claim <dir> "<one-line task>"`.
       - `OK <repoRoot>` means you have the main checkout; work there.
       - `USE_WORKTREE <path> <branch>` means another pane is already working in this repo. `cd` to
         <path> and do all of your work there, on <branch>. Never edit the main checkout in that case.
       Use `onyx-pane who <dir>` to see which panes are in a repo and what they are doing.
    2. Always push with `onyx-pane push`; never `git push --force`, and never plain `git push`.
       It serializes pushes per repo and rebases onto the latest remote first.
    3. If `onyx-pane push` prints `CONFLICT <files>`, the rebase stopped in place. Resolve each file
       keeping the intent of BOTH sides, `git add` it, `git rebase --continue`, run the project's
       tests, then run `onyx-pane push` again. If the right resolution is a judgment call (both sides
       changed the same logic in different ways), stop and ask the user before continuing.
       `NO_REMOTE` means the repo has no origin; tell the user the branch is ready to merge.
    4. When your task is done and pushed, run `onyx-pane release`.
    5. The repository's own CLAUDE.md rules (for example ship or deploy scripts) win over these
       generic push steps when they conflict.
    """

    /// Writes `pane-prompt.md` into `dir` (creating it) and returns the file URL.
    public static func write(to dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pane-prompt.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
