#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ROOT="${HOME}/Library/Application Support/MacOSTypingSounds/Profiles"
DEST_ROOT="${REPO_ROOT}/MacOSTypingSounds/DefaultPacks"

typeset -A PACK_PROFILE_IDS=(
  FalloutClassic "4FEEAD6C-CCE7-4B65-81C2-CB6D2D1D03AC"
  Cyberpunk "848AA39E-83C8-4AB7-AE67-D84D857AC82D"
  Minecraft "2C0EF3DF-471B-4900-937B-4B1F3E3E4279"
)

typeset -A PACK_DISPLAY_NAMES=(
  FalloutClassic "Fallout Classic"
  Cyberpunk "Cyberpunk"
  Minecraft "Minecraft"
)

SLOT_IDS=(
  typing
  enter
  backspace
  tab
  space
  escape
  launch
  quit
)

function plist_string_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  echo "$value"
}

function plist_add_string() {
  local plist_path="$1"
  local value="$2"
  local plist_file="$3"
  local escaped
  escaped="$(plist_string_escape "$value")"
  /usr/libexec/PlistBuddy -c "Add ${plist_path} string \"${escaped}\"" "$plist_file" >/dev/null
}

function plist_print_value() {
  local key_path="$1"
  local plist_file="$2"
  /usr/libexec/PlistBuddy -c "Print ${key_path}" "$plist_file" 2>/dev/null
}

mkdir -p "$DEST_ROOT"

for pack_dir in FalloutClassic Cyberpunk Minecraft; do
  profile_id="${PACK_PROFILE_IDS[$pack_dir]}"
  display_name="${PACK_DISPLAY_NAMES[$pack_dir]}"
  source_profile_dir="${SOURCE_ROOT}/${profile_id}"
  source_assets_dir="${source_profile_dir}/Assets"
  source_config_plist="${source_profile_dir}/profile-config.plist"
  destination_pack_dir="${DEST_ROOT}/${pack_dir}"
  destination_manifest="${destination_pack_dir}/pack-manifest.plist"

  if [[ ! -d "$source_assets_dir" || ! -f "$source_config_plist" ]]; then
    echo "Missing source profile data for ${display_name} (${profile_id})." >&2
    exit 1
  fi

  rm -rf "$destination_pack_dir"
  mkdir -p "${destination_pack_dir}/Assets"
  cp "${source_assets_dir}/"* "${destination_pack_dir}/Assets/"

  cat > "$destination_manifest" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
PLIST

  /usr/libexec/PlistBuddy -c "Add :schemaVersion integer 1" "$destination_manifest" >/dev/null
  plist_add_string ":displayName" "$display_name" "$destination_manifest"
  /usr/libexec/PlistBuddy -c "Add :assets array" "$destination_manifest" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :slotAssignments dict" "$destination_manifest" >/dev/null
  for slot_id in "${SLOT_IDS[@]}"; do
    /usr/libexec/PlistBuddy -c "Add :slotAssignments:${slot_id} array" "$destination_manifest" >/dev/null
  done

  typeset -A asset_id_to_file_name
  asset_index=0
  while true; do
    if ! asset_id="$(plist_print_value ":assets:${asset_index}:assetID" "$source_config_plist")"; then
      break
    fi
    stored_file_name="$(plist_print_value ":assets:${asset_index}:storedFileName" "$source_config_plist")"
    display_file_name="$(plist_print_value ":assets:${asset_index}:displayName" "$source_config_plist")"
    source_extension="$(plist_print_value ":assets:${asset_index}:sourceExtension" "$source_config_plist" || true)"

    /usr/libexec/PlistBuddy -c "Add :assets:${asset_index} dict" "$destination_manifest" >/dev/null
    plist_add_string ":assets:${asset_index}:fileName" "$stored_file_name" "$destination_manifest"
    plist_add_string ":assets:${asset_index}:displayName" "$display_file_name" "$destination_manifest"
    if [[ -n "${source_extension:-}" ]]; then
      plist_add_string ":assets:${asset_index}:sourceExtension" "$source_extension" "$destination_manifest"
    fi

    asset_id_to_file_name[$asset_id]="$stored_file_name"
    asset_index=$((asset_index + 1))
  done

  for slot_id in "${SLOT_IDS[@]}"; do
    source_slot_index=0
    destination_slot_index=0
    while true; do
      if ! slot_asset_id="$(plist_print_value ":slotAssignments:${slot_id}:${source_slot_index}" "$source_config_plist")"; then
        break
      fi
      stored_file_name="${asset_id_to_file_name[$slot_asset_id]-}"
      if [[ -n "$stored_file_name" ]]; then
        plist_add_string ":slotAssignments:${slot_id}:${destination_slot_index}" "$stored_file_name" "$destination_manifest"
        destination_slot_index=$((destination_slot_index + 1))
      fi
      source_slot_index=$((source_slot_index + 1))
    done
  done

  echo "Synced ${display_name} -> ${destination_pack_dir}"
done

echo "Default pack sync complete."
