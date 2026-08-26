#!/usr/bin/env sh
#
# Write one version number into every place that carries it.
#
# The version lives in five spots (TOC, Config, locale, and two in UI.lua).
# Editing them by hand is how they drift apart, so this is the single source of
# truth -- used both locally and by the GitHub workflow, so the two can never
# disagree.
#
#   ./scripts/set-version.sh 2.3.31

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>   e.g. $0 2.3.31" >&2
    exit 1
fi

# Reject anything that is not X.Y.Z: a malformed version silently produces a
# broken TOC that the client refuses to load.
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: '$VERSION' is not X.Y.Z" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

replace() {
    file="$1"
    pattern="$2"
    if [ ! -f "$file" ]; then
        echo "error: $file not found" >&2
        exit 1
    fi
    before=$(md5sum "$file" | cut -d' ' -f1)
    sed -i -E "$pattern" "$file"
    after=$(md5sum "$file" | cut -d' ' -f1)
    if [ "$before" = "$after" ]; then
        echo "warning: nothing changed in $file -- check the pattern" >&2
    fi
}

replace OxedHub.toc                 "s/^## Version:.*/## Version: $VERSION/"
replace Core/Config.lua             "s/VERSION = \"[0-9]+\.[0-9]+\.[0-9]+\"/VERSION = \"$VERSION\"/"
replace Locales/ENLocalization.lua  "s/L\[\"RELEASE_TITLE\"\] = \"Release [0-9]+\.[0-9]+\.[0-9]+\"/L[\"RELEASE_TITLE\"] = \"Release $VERSION\"/"
replace UI/UI.lua                   "s/RELEASE NOTES \(RELEASE [0-9]+\.[0-9]+\.[0-9]+\)/RELEASE NOTES (RELEASE $VERSION)/"
replace UI/UI.lua                   "s/or \"Release [0-9]+\.[0-9]+\.[0-9]+\"/or \"Release $VERSION\"/"

echo "Version set to $VERSION:"
grep -rn "$VERSION" OxedHub.toc Core/Config.lua Locales/ENLocalization.lua UI/UI.lua
