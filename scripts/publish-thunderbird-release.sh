#!/usr/bin/env bash
# Poll Mozilla for the latest Thunderbird, wrap it in a .deb, publish a GitHub Release.
#
# Usage (CI):
#   ./scripts/publish-thunderbird-release.sh
#
# Env:
#   DRY_RUN=1       Log actions only; do not build or publish
#   FORCE_BUILD=1   Rebuild and upload even if the GitHub release already exists
#   DEBVERSION      Ubuntu revision in the .deb version (default: 1)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PACKAGE="${PACKAGE:-thunderbird}"
DEBVERSION="${DEBVERSION:-1}"
ARCH="amd64"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required" >&2
  exit 1
fi

upstream="$(python3 "$REPO_ROOT/mozillapackager.py" -p "$PACKAGE" -a getversion | tail -n 1 | tr -d '[:space:]')"

if [[ ! "$upstream" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "error: unexpected upstream version: ${upstream:-<empty>}" >&2
  exit 1
fi

tag="v${upstream}"
deb="${PACKAGE}-mozilla-build_${upstream}-0ubuntu${DEBVERSION}_${ARCH}.deb"

echo "==> upstream ${PACKAGE}: ${upstream}"
echo "==> release tag: ${tag}"
echo "==> expected .deb: ${deb}"

release_exists=0
if gh release view "$tag" >/dev/null 2>&1; then
  release_exists=1
  echo "==> GitHub release ${tag} already exists"
else
  echo "==> no GitHub release for ${tag}"
fi

if [[ -n "${FORCE_BUILD:-}" && "${FORCE_BUILD}" != "0" ]]; then
  echo "==> FORCE_BUILD=1: will wrap and publish"
elif [[ "$release_exists" -eq 1 ]]; then
  echo "==> up to date; no publish needed"
  exit 0
fi

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "==> DRY_RUN=1: would build ${deb} and publish ${tag}"
  exit 0
fi

echo "==> wrapping official Mozilla ${PACKAGE} ${upstream} as a .deb"
python3 "$REPO_ROOT/mozillapackager.py" \
  -p "$PACKAGE" \
  -a builddeb \
  --no-install \
  -b "$REPO_ROOT" \
  -v "$DEBVERSION"

if [[ ! -f "$REPO_ROOT/$deb" ]]; then
  echo "error: expected .deb not found at ${REPO_ROOT}/${deb}" >&2
  ls -lh "$REPO_ROOT"/*.deb 2>/dev/null || true
  exit 1
fi

notes="Official Mozilla ${PACKAGE^} ${upstream}, packaged as \`${PACKAGE}-mozilla-build\`.

This is the unmodified Mozilla Linux x86_64 tarball, wrapped in a .deb by ubuntuzilla so it can be installed alongside (or instead of) the distro/snap package.

\`\`\`bash
sudo apt install ./${deb}
\`\`\`
"

if [[ "$release_exists" -eq 1 ]]; then
  gh release upload "$tag" "$REPO_ROOT/$deb" --clobber
  gh release edit "$tag" --notes "$notes" || true
else
  gh release create "$tag" "$REPO_ROOT/$deb" \
    --title "Thunderbird ${upstream}" \
    --notes "$notes"
fi

echo "==> published ${tag} (${deb})"
