#!/bin/bash
# Cut a ClipHistory release end-to-end:
#   bump version -> commit -> push -> build .dmg -> create GitHub release.
#
# Usage:  ./release.sh [options] <version>
#   <version>            e.g. 1.2  (CFBundleShortVersionString)
#
# Options:
#   -m, --notes <text>        Release notes (markdown string).
#   -F, --notes-file <path>   Read release notes from a file.
#   -y, --yes                 Skip the confirmation prompt.
#   -n, --dry-run             Print the steps without changing anything.
#       --no-commit           Don't bump/commit/push; release from current HEAD.
#       --no-release          Build the .dmg but don't create the GitHub release.
#       --prerelease          Mark the GitHub release as a pre-release.
#   -h, --help                Show this help.
#
# Examples:
#   ./release.sh 1.2 -m "Fix paste timing on slow apps"
#   ./release.sh 1.2 -F notes.md -y
#   ./release.sh 1.2 --dry-run
set -euo pipefail
cd "$(dirname "$0")"

REPO="banegasn/clip-history"
PLIST="Info.plist"

# ---- defaults ----
VERSION=""
NOTES=""
NOTES_FILE=""
ASSUME_YES=0
DRY_RUN=0
DO_COMMIT=1
DO_RELEASE=1
PRERELEASE=0

err()  { printf "\033[31merror:\033[0m %s\n" "$*" >&2; exit 1; }
info() { printf "\033[36m▸\033[0m %s\n" "$*"; }
run()  { if [ "$DRY_RUN" -eq 1 ]; then printf "  \033[2m(dry-run)\033[0m %s\n" "$*"; else eval "$*"; fi; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^set -euo.*//'; exit "${1:-0}"; }

# ---- parse args ----
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--notes)       NOTES="${2:-}"; shift 2 ;;
        -F|--notes-file)  NOTES_FILE="${2:-}"; shift 2 ;;
        -y|--yes)         ASSUME_YES=1; shift ;;
        -n|--dry-run)     DRY_RUN=1; shift ;;
        --no-commit)      DO_COMMIT=0; shift ;;
        --no-release)     DO_RELEASE=0; shift ;;
        --prerelease)     PRERELEASE=1; shift ;;
        -h|--help)        usage 0 ;;
        -*)               err "unknown option: $1 (try --help)" ;;
        *)                if [ -z "$VERSION" ]; then VERSION="$1"; else err "unexpected argument: $1"; fi; shift ;;
    esac
done

[ -n "$VERSION" ] || { usage 1; }
echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || err "version must look like 1.2 or 1.2.3 (got '$VERSION')"
[ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ] && err "notes file not found: $NOTES_FILE"

TAG="v${VERSION}"
DMG="ClipHistory-${VERSION}.dmg"

# ---- preflight ----
command -v gh >/dev/null || err "gh CLI not found"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || err "not a git repository"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "master" ] && err "refusing to release from 'master' — switch to a release branch"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    err "release $TAG already exists"
fi

# Resolve notes: explicit string > file > sensible default.
if [ -z "$NOTES" ] && [ -z "$NOTES_FILE" ]; then
    NOTES="ClipHistory ${VERSION}"
fi

# ---- summary ----
echo
info "Release plan"
echo "  repo:       $REPO"
echo "  version:    $VERSION   (tag $TAG)"
echo "  branch:     $BRANCH"
echo "  commit:     $([ "$DO_COMMIT" -eq 1 ] && echo 'bump Info.plist + commit + push' || echo 'skip (use current HEAD)')"
echo "  dmg:        $DMG"
echo "  release:    $([ "$DO_RELEASE" -eq 1 ] && echo "create on GitHub$([ "$PRERELEASE" -eq 1 ] && echo ' (prerelease)')" || echo 'skip')"
echo "  notes:      ${NOTES_FILE:-${NOTES}}"
if [ "$DO_COMMIT" -eq 1 ]; then
    echo "  pending changes to be committed:"
    git status --short | sed 's/^/    /' || true
fi
echo

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Proceed? [y/N] " ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "aborted."; exit 1 ;; esac
fi

# ---- 1. bump version + commit + push ----
if [ "$DO_COMMIT" -eq 1 ]; then
    CUR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST" 2>/dev/null || echo 0)"
    case "$CUR_BUILD" in (*[!0-9]*|'') CUR_BUILD=0 ;; esac
    NEW_BUILD=$((CUR_BUILD + 1))
    info "Bumping $PLIST -> version $VERSION (build $NEW_BUILD)"
    run "/usr/libexec/PlistBuddy -c 'Set CFBundleShortVersionString $VERSION' '$PLIST'"
    run "/usr/libexec/PlistBuddy -c 'Set CFBundleVersion $NEW_BUILD' '$PLIST'"

    info "Committing and pushing to $BRANCH"
    run "git add -A"
    run "git commit -m 'Release ${VERSION}'"
    run "git push"
fi

# ---- 2. build the dmg ----
info "Building $DMG"
run "./make-dmg.sh '$VERSION'"

# ---- 3. create the GitHub release ----
if [ "$DO_RELEASE" -eq 1 ]; then
    GH_ARGS="$TAG '$DMG' --repo '$REPO' --title 'ClipHistory ${VERSION}' --latest"
    [ "$PRERELEASE" -eq 1 ] && GH_ARGS="$GH_ARGS --prerelease"
    if [ -n "$NOTES_FILE" ]; then
        GH_ARGS="$GH_ARGS --notes-file '$NOTES_FILE'"
    else
        GH_ARGS="$GH_ARGS --notes \"$NOTES\""
    fi
    info "Creating GitHub release $TAG"
    run "gh release create $GH_ARGS"
fi

echo
info "Done."
if [ "$DO_RELEASE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "  https://github.com/${REPO}/releases/tag/${TAG}"
fi
exit 0
