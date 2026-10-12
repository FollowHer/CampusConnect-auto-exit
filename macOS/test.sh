#!/bin/zsh
set -euo pipefail
task_dir="${0:A:h}"
task_tests="$(mktemp -d "${TMPDIR:-/tmp}/campus-tests.XXXXXX")"
trap 'rm -rf "${task_tests}"' EXIT
cd "${task_tests}"
xcrun swiftc -swift-version 5 "${task_dir}/source/Core.swift" "${task_dir}/source/Tests.swift" \
  -framework JavaScriptCore -o "${task_tests}/campus-tests"
"${task_tests}/campus-tests"
