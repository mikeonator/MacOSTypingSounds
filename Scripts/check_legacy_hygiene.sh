#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DENYLIST=(
  "FalloutTerminalKeyMapper"
  "pipboy_icon"
  "Copyright © 2015 mdt"
  "ORGANIZATIONNAME = mdt"
)

EXCLUDES=(
  "!MacOSTypingSounds/ThirdParty/**"
  "!MacOSTypingSounds/GeneratedIcons/**"
  "!MacOSTypingSounds/DefaultPacks/**"
  "!Scripts/check_legacy_hygiene.sh"
)

cd "$REPO_ROOT"

hits=0
for token in "${DENYLIST[@]}"; do
  if rg --line-number --fixed-strings --hidden \
    --glob "${EXCLUDES[1]}" \
    --glob "${EXCLUDES[2]}" \
    --glob "${EXCLUDES[3]}" \
    --glob "${EXCLUDES[4]}" \
    "$token" MacOSTypingSounds MacOSTypingSoundsTests Scripts README.md MacOSTypingSounds.xcodeproj/project.pbxproj; then
    echo "[legacy-hygiene] Forbidden legacy token found: $token" >&2
    hits=1
  fi
done

if [[ "$hits" -ne 0 ]]; then
  echo "[legacy-hygiene] Failed." >&2
  exit 1
fi

echo "[legacy-hygiene] Passed."
