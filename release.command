#!/bin/bash
# =============================================================================
#  release.command — AI Compare one-button release script
#  Double-click this file in Finder, or run: bash release.command
# =============================================================================
set -euo pipefail

# ── Resolve project root (works whether double-clicked or run from terminal) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Config ────────────────────────────────────────────────────────────────────
SCHEME="AI Tools"
PROJECT="AI Tools.xcodeproj"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
BUILD_DIR="build"
DIST_DIR="dist"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
step()  { echo -e "\n${CYAN}▶ $*${NC}"; }
ok()    { echo -e "${GREEN}✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $*${NC}"; }
die()   { echo -e "${RED}✗ $*${NC}"; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
step "Preflight checks"
command -v xcodebuild >/dev/null || die "xcodebuild not found — install Xcode."
command -v gh          >/dev/null || die "'gh' not found — install: brew install gh"
command -v hdiutil     >/dev/null || die "hdiutil not found (unexpected on macOS)."

git diff --quiet || warn "You have uncommitted changes — they won't be included in the archive."
ok "Tools found"

# ── Determine next version ────────────────────────────────────────────────────
step "Calculating next version"
LATEST_TAG=$(git tag --sort=-version:refname | grep '^v[0-9]' | head -1 || true)
if [[ -z "$LATEST_TAG" ]]; then
    LATEST_TAG="v1.0.0"
    warn "No existing tags found — starting from v1.0.0"
fi

BASE_VERSION="${LATEST_TAG#v}"          # strip leading 'v'
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"
PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_TAG="v${NEW_VERSION}"

echo "  Previous tag : ${LATEST_TAG}"
echo "  New version  : ${NEW_VERSION} (${NEW_TAG})"

# Confirm before proceeding
echo ""
read -r -p "  Proceed with release ${NEW_TAG}? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Bump version in Xcode project ─────────────────────────────────────────────
step "Bumping MARKETING_VERSION → ${NEW_VERSION}"
xcrun agvtool new-marketing-version "$NEW_VERSION" > /dev/null
ok "Version bumped"

# ── Archive ───────────────────────────────────────────────────────────────────
step "Archiving (this takes a minute…)"
ARCHIVE_PATH="${BUILD_DIR}/AI-Tools.xcarchive"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -project        "$PROJECT" \
    -scheme         "$SCHEME" \
    -configuration  Release \
    -archivePath    "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Automatic \
    -quiet
ok "Archive created at ${ARCHIVE_PATH}"

# ── Export ────────────────────────────────────────────────────────────────────
step "Exporting with Developer ID signing"
EXPORT_PATH="${BUILD_DIR}/export"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath        "$ARCHIVE_PATH" \
    -exportPath         "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -quiet
APP_PATH="${EXPORT_PATH}/AI Tools.app"
[[ -d "$APP_PATH" ]] || die "Export failed — AI Tools.app not found at ${EXPORT_PATH}"
ok "App exported"

# ── Create DMG ────────────────────────────────────────────────────────────────
step "Creating DMG"
mkdir -p "$DIST_DIR"
DMG_NAME="AI-Tools_${NEW_VERSION}_macOS_arm64.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "AI Compare" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    -o "$DMG_PATH" > /dev/null
ok "DMG created: ${DMG_NAME}"

# ── SHA256 checksum ───────────────────────────────────────────────────────────
step "Generating SHA256 checksum"
SHA_NAME="AI-Tools_${NEW_VERSION}_SHA256SUMS.txt"
SHA_PATH="${DIST_DIR}/${SHA_NAME}"
shasum -a 256 "$DMG_PATH" | awk -v name="$DMG_NAME" '{print $1 "  " name}' > "$SHA_PATH"
ok "Checksum: $(cat "$SHA_PATH")"

# ── Commit version bump ───────────────────────────────────────────────────────
step "Committing version bump"
git add "${PROJECT}/project.pbxproj"
git commit -m "Bump version to ${NEW_VERSION}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
ok "Committed"

# ── Tag & push ────────────────────────────────────────────────────────────────
step "Tagging and pushing"
git tag "$NEW_TAG"
git push origin HEAD
git push origin "$NEW_TAG"
ok "Pushed tag ${NEW_TAG} to origin"

# ── GitHub release ────────────────────────────────────────────────────────────
step "Creating GitHub release ${NEW_TAG}"
gh release create "$NEW_TAG" \
    "${DMG_PATH}" \
    "${SHA_PATH}" \
    --title "AI Compare ${NEW_TAG}" \
    --notes "## AI Compare ${NEW_TAG}

### What's new
- Bug fixes and performance improvements

---
_Built with Xcode · Signed with Developer ID · macOS arm64_"

RELEASE_URL=$(gh release view "$NEW_TAG" --json url -q .url 2>/dev/null || echo "(see GitHub)")
ok "GitHub release live: ${RELEASE_URL}"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  AI Compare ${NEW_TAG} released!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
