#!/bin/zsh
set -euo pipefail
task_source_dir="${0:A:h}"
task_output_dir="${1:-${task_source_dir:h}}"
task_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/campus-build.XXXXXX")"
trap 'rm -rf "${task_build_dir}"' EXIT
task_app="${task_output_dir}/CampusConnect.app"
mkdir -p "${task_app}/Contents/MacOS" "${task_app}/Contents/Resources" "${task_build_dir}"
cp "${task_source_dir}/PortalBootstrap.js" "${task_app}/Contents/Resources/"
cp "${task_source_dir}/../../LICENSE" "${task_app}/Contents/Resources/LICENSE.txt"
cp "${task_source_dir}/Info.plist" "${task_app}/Contents/Info.plist"
for task_arch in arm64 x86_64; do
xcrun swiftc -swift-version 5 -O -target "${task_arch}-apple-macosx14.0" \
  "${task_source_dir}/Core.swift" "${task_source_dir}/WiFi.swift" \
  "${task_source_dir}/Connectivity.swift" "${task_source_dir}/CampusProxy.swift" "${task_source_dir}/Portal.swift" "${task_source_dir}/App.swift" \
  -framework SwiftUI -framework AppKit -framework CoreWLAN \
  -framework CoreLocation -framework WebKit -framework Network -framework ServiceManagement \
  -o "${task_build_dir}/CampusConnect-${task_arch}"
done
xcrun lipo -create "${task_build_dir}/CampusConnect-arm64" "${task_build_dir}/CampusConnect-x86_64" \
  -output "${task_app}/Contents/MacOS/CampusConnect"
if [ -f "${task_source_dir}/AppIcon.icns" ]; then cp "${task_source_dir}/AppIcon.icns" "${task_app}/Contents/Resources/"; fi
codesign --force --sign - --identifier local.campusconnect.mac "${task_app}"
codesign --verify --deep --strict "${task_app}"
print "Built: ${task_app}"
