#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_SHA:?}"
: "${GH_TOKEN:?}"
release_tag="v2.0.4-auto-exit"
if [[ "$GITHUB_REPOSITORY" != "FollowHer/CampusConnect-auto-exit" ]]; then
  echo 'Publishing is only configured for the FollowHer fork.' >&2
  exit 1
fi
if gh release view "$release_tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "Release $release_tag already exists; preserving its published files."
  exit 0
fi
(
  cd release
  sha256sum ./*.exe ./*.zip | sed 's|  ./|  |' > SHA256SUMS.txt
)
gh release create "$release_tag" release/* \
  --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
  --title 'FollowHer 自动退出版 2.0.4 · Windows / macOS' \
  --notes-file docs/RELEASE-v2.0.4-auto-exit.md
