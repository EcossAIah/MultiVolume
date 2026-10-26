#!/usr/bin/env bash
#
# Publishes the version in Resources/Info.plist as a GitHub release and points
# the Homebrew cask at it.
#
#   ./release.sh
#
# Needs a clean main branch, the GitHub CLI signed in, and the certificate from
# ./make-signing-cert.sh. Release notes come from that version's CHANGELOG.md
# section.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
ZIP="build/MultiVolume-$VERSION.zip"
CASK="Casks/multivolume.rb"

# ---------------------------------------------------------------- checks

[ "$(git branch --show-current)" = "main" ] || { echo "ERROR: not on main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "ERROR: working tree not clean" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "ERROR: tag $TAG already exists; bump the version in Resources/Info.plist" >&2
  exit 1
fi
security find-certificate -c "EcossAIah Self-Signed" >/dev/null 2>&1 \
  || { echo "ERROR: signing certificate missing; run ./make-signing-cert.sh" >&2; exit 1; }

NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' CHANGELOG.md)"
[ -n "$NOTES" ] || { echo "ERROR: no CHANGELOG.md section for $VERSION" >&2; exit 1; }

# ---------------------------------------------------------------- build

swift test
./build.sh

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

# ---------------------------------------------------------------- cask

sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"
git add "$CASK"
git commit -m "chore: release $VERSION"

# ---------------------------------------------------------------- publish

git tag -a "$TAG" -m "MultiVolume $VERSION"
git push origin main "$TAG"

gh release create "$TAG" "$ZIP" \
  --title "MultiVolume $VERSION" \
  --notes "$NOTES

### Install or update

\`\`\`sh
brew tap EcossAIah/multivolume https://github.com/EcossAIah/MultiVolume
brew install --cask multivolume   # first time
brew upgrade --cask multivolume   # later updates
\`\`\`

Or download \`MultiVolume-$VERSION.zip\` below, unzip, and drag the app to Applications.

### Checksum

\`\`\`
SHA-256  $SHA  MultiVolume-$VERSION.zip
\`\`\`"

echo
echo "Released $TAG"
