#!/usr/bin/env bash
# Cut a tester release: bump the .toc version, zip the addon, tag, push,
# and publish a GitHub Release that WowUp picks up as an update.
# Usage: tools/release.sh 0.3.2 ["release notes"]
set -euo pipefail

VERSION="${1:?usage: tools/release.sh <version> [notes]}"
NOTES="${2:-}"
REPO="frznfngrs/SanctuaryUI"
GH_USER="frznfngrs"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOC="$ROOT/SanctuaryUI/SanctuaryUI.toc"
ZIP="$ROOT/dist/SanctuaryUI-$VERSION.zip"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty; commit first." >&2; exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "Tag v$VERSION already exists." >&2; exit 1
fi

# Syntax-check addon Lua (skip bundled libs).
find SanctuaryUI -name '*.lua' -not -path '*/libs/*' -print0 | xargs -0 -n1 luac5.1 -p

sed -i "s/^## Version: .*/## Version: $VERSION/" "$TOC"

mkdir -p dist
python3 - "$ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dp, dns, fns in os.walk("SanctuaryUI"):
        dns[:] = [d for d in dns if not d.startswith(".")]
        for f in fns:
            if f.startswith("."):
                continue
            p = os.path.join(dp, f)
            z.write(p, p)
print("built", out)
PY

git add "$TOC"
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

GH_TOKEN="$(gh auth token -u "$GH_USER")" gh release create "v$VERSION" "$ZIP" \
  -R "$REPO" --title "SanctuaryUI $VERSION" --notes "${NOTES:-Tester build $VERSION}"

echo "Released v$VERSION -> https://github.com/$REPO/releases/tag/v$VERSION"
