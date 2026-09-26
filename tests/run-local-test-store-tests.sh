#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir="$(mktemp -d /tmp/tracker-local-tests.XXXXXX)"
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$test_build_dir/modules" \
  TrackerDashboard/Models/*.swift \
  TrackerDashboard/Storage/*.swift \
  TrackerDashboard/Networking/TrackerAPIClient.swift \
  TrackerDashboard/Networking/LocalTestStore.swift \
  tests/LocalTestStoreTests.swift \
  -o "$test_build_dir/local-tests"
"$test_build_dir/local-tests"
