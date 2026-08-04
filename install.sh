#!/usr/bin/env bash
# Installs Chronie Lite into the World of Warcraft AddOns folder you run it from.
#
#   cd "/Applications/World of Warcraft/_retail_/Interface/AddOns"
#   curl -fsSL https://raw.githubusercontent.com/dipasqualew/chronie-lite/main/install.sh | bash
#
# Run it again to update. It downloads the current main branch, then replaces ./chronie
# wholesale — the addon folder holds nothing but the addon, so there is nothing in there to
# preserve. Everything the addon has recorded lives in WTF/, several directories up from here,
# and is not touched.
#
# The folder it writes is `chronie`, which is the same folder the full Chronie uses. That is
# deliberate: the two are the same addon with different switches, they share ChronieDB, and
# replacing one with the other keeps every lockout, segment and memory already recorded. It
# does mean this overwrites a full Chronie install, which is what "replace" means here.
set -euo pipefail

REPOSITORY="${CHRONIE_LITE_REPOSITORY:-dipasqualew/chronie-lite}"
BRANCH="${CHRONIE_LITE_BRANCH:-main}"
FOLDER="chronie"

# Refuse to install anywhere but an AddOns folder. Getting this wrong scatters an addon across
# whatever directory the shell happened to be in, and the failure is silent — the game simply
# never sees it. `--force` is for the person who knows better, which includes anyone testing
# this script.
if [ "$(basename "$PWD")" != "AddOns" ] && [ "${1:-}" != "--force" ]; then
    echo "This installs into the folder you run it from, and that folder should be your" >&2
    echo "World of Warcraft AddOns folder. You are in:" >&2
    echo "    $PWD" >&2
    echo >&2
    echo "Typically:" >&2
    echo "    macOS    /Applications/World of Warcraft/_retail_/Interface/AddOns" >&2
    echo "    Windows  C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns" >&2
    echo >&2
    echo "cd there and run it again, or pass --force to install here anyway." >&2
    exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

echo "Downloading Chronie Lite ($REPOSITORY@$BRANCH)..."
# The whole archive, then one folder out of it. Asking tar for `*/chronie` directly would be
# tidier and is not portable: BSD tar matches wildcards in an extraction pattern by default and
# GNU tar wants --wildcards, so the one command that works everywhere is the one that unpacks
# the lot. It is a few hundred kilobytes of Lua either way.
curl -fsSL "https://codeload.github.com/$REPOSITORY/tar.gz/refs/heads/$BRANCH" \
    | tar -xz -C "$staging" --strip-components=1

# What lands in the game is what the client loads and nothing else: the specs, the workflow and
# this script stay in the repository they came from.
if [ ! -f "$staging/$FOLDER/chronie.toc" ]; then
    echo "The download did not contain $FOLDER/chronie.toc — nothing has been changed." >&2
    exit 1
fi

# Replaced rather than merged, so a file dropped from a later release does not linger and get
# loaded by a .toc that no longer lists it. Swapped in only once the download has been checked
# above, so a failed download leaves the working install alone.
rm -rf "./$FOLDER"
mv "$staging/$FOLDER" "./$FOLDER"

echo "Installed to $PWD/$FOLDER"
echo "Reload the game (or /reload if it is running) and type /chronie for the commands."
