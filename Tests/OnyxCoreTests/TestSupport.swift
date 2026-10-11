import Foundation
@testable import OnyxCore

/// A fresh ONYX_HOME under the temp dir.
func tempPaths() -> OnyxPaths {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-\(UUID().uuidString)")
    return OnyxPaths(env: ["ONYX_HOME": dir.path])
}

func claim(_ id: String, repo: String = "/r", worktree: String? = nil) -> PaneClaim {
    PaneClaim(paneId: id, repoRoot: repo, worktree: worktree, branch: "main", task: "t",
              updatedAt: Date(timeIntervalSince1970: 0))
}
