#!/bin/zsh
set -euo pipefail
task_dir="${0:A:h}"
task_build="$(mktemp -d "${TMPDIR:-/tmp}/campus-lifecycle-tests.XXXXXX")"
trap 'rm -rf "${task_build}"' EXIT
xcrun swiftc -swift-version 5 -D CAMPUS_LIFECYCLE_TESTS \
  "${task_dir}/source/Core.swift" "${task_dir}/source/WiFi.swift" \
  "${task_dir}/source/WiredAuthentication.swift" "${task_dir}/source/Connectivity.swift" \
  "${task_dir}/source/CampusProxy.swift" "${task_dir}/source/Portal.swift" \
  "${task_dir}/source/App.swift" "${task_dir}/source/LifecycleTests.swift" \
  -framework SwiftUI -framework AppKit -framework CoreWLAN -framework CoreLocation \
  -framework SystemConfiguration -framework WebKit -framework Network -framework ServiceManagement \
  -o "${task_build}/lifecycle-tests"
"${task_build}/lifecycle-tests"
