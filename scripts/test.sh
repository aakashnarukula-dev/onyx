#!/bin/zsh
# The Command Line Tools ship no XCTest, so tests use Swift Testing. The explicit
# plugin path works around CLT intermittently missing the TestingMacros plugin.
set -e
cd "${0:A:h}/.."
source scripts/env.sh
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
