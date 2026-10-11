import Foundation
@testable import OnyxCore

/// A fresh ONYX_HOME under the temp dir.
func tempPaths() -> OnyxPaths {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-\(UUID().uuidString)")
    return OnyxPaths(env: ["ONYX_HOME": dir.path])
}
