#!/bin/zsh
set -euo pipefail
task_dir="${0:A:h}"
task_build="$(mktemp -d "${TMPDIR:-/tmp}/campus-webkit-tests.XXXXXX")"
trap 'rm -rf "${task_build}"' EXIT
xcrun swiftc -swift-version 5 "${task_dir}/source/Core.swift" "${task_dir}/source/WebKitTests.swift" -framework AppKit -framework WebKit -o "${task_build}/webkit-tests"
"${task_build}/webkit-tests"
