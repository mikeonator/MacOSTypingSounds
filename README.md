# MacOSTypingSounds

Mac menu bar app that plays keyboard and app event sounds with profile-based routing.

Current release target: `v3.0.0`.

## v3.0.0 Highlights

- Three bundled default packs with missing-only seeding (`Fallout Classic`, `Cyberpunk`, `Minecraft`).
- OGG import/conversion support across pack import workflows.
- Single-window sidebar Preferences flow with inline `Sounds Library`, `App Routing`, and `App Behavior`.
- Updated Apple-native icon pipeline using Icon Composer export + asset catalog iconstack assets.
- Legacy fork reference cleanup and denylist hygiene gate.

## What It Does

- Plays typing sounds from a selected/default profile.
- Supports per-app profile routing by bundle identifier.
- Plays assigned profile sounds for app launch and app quit events.
- Bundles three editable default packs on first run:
  - `Fallout Classic`
  - `Cyberpunk`
  - `Minecraft`
- Lets you run in two modes:
  - `Play SFX in all apps` (unassigned apps use default profile)
  - `Play SFX in assigned apps only` (unassigned apps are silent)
- Supports profile management (create, duplicate, rename, delete).
- Supports flat soundpack import (recursive import; folder names are ignored).
- Uses a single sidebar Preferences window (no nested editor popups):
  - `Profiles`
  - `Sounds Library` (full slot mapping + profile library workflow)
  - `App Routing` (full inline assignment CRUD)
  - `App Behavior` (playback controls + permission status/actions)

## Sound Import Support

- Supported file types: `.mp3`, `.wav`, `.m4a`, `.aiff`, `.ogg`
- `.ogg` files are converted to `.wav` on import (Vorbis via `stb_vorbis`, other decodable OGG codecs via CoreAudio).

## Bundled Default Packs

- Bundled resources live in:
  - `/Users/mikeonator/Documents/Code/MacOSTypingSounds/MacOSTypingSounds/DefaultPacks`
- Each pack has:
  - `pack-manifest.plist` (display name, library assets, slot assignments)
  - `Assets/` (audio files)
- Seeding behavior:
  - Missing-only seeding at startup
  - Existing user profiles are never overwritten
  - Seeded packs are normal editable profiles

Regenerate bundled pack snapshots from local imported profiles:

```bash
./Scripts/sync_defaultpacks_from_profiles.sh
```

## Slot Fallback Behavior

- Empty key slots (`enter`, `backspace`, `tab`, `space`, `escape`) fall back to `typing`.
- Empty `launch` / `quit` fall back to bundled power sounds.
- Empty `typing` falls back to bundled typing sounds.

## Permissions

For global keyboard/event behavior, grant the app:

- Accessibility
- Input Monitoring

You can request these from `Preferences -> App Behavior` or in macOS Privacy & Security settings.

Menu bar behavior:

- Permission warning line appears only when one or both permissions are missing.
- Current app route line appears only when opening the menu while holding `Option`.

## Build And Run

### Xcode

1. Open `MacOSTypingSounds.xcodeproj`.
2. Build/run the `MacOSTypingSounds` scheme.

### CLI

```bash
xcodebuild -project MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

### Icon Pipeline (Apple Native)

Uses Icon Composer package + native `sips`/`iconutil`:

```bash
./Scripts/generate_icons_native.sh \
  /Users/mikeonator/Pictures/MacOSTypingSoundsIcon.icon \
  /Users/mikeonator/Desktop/MacOSTypingSoundsMenuBarIcon.svg
```

Outputs:

- App icon stack assets synced to `MacOSTypingSounds/Images.xcassets/AppIcon.iconstack` + `AppIcon_Assets`
- Canonical Icon Composer package at `Branding/AppIcon.icon`
- Menu icon template PDF at `MacOSTypingSounds/MenuBarIconTemplate.pdf`
- Distribution `.icns` at `MacOSTypingSounds/GeneratedIcons/MacOSTypingSounds.icns`

## Quick Usage Flow

1. Launch the app.
2. Open menu bar item -> `Preferences…`.
3. Create/select a profile.
4. Import a pack (`Import Pack…`) or add files.
5. Use `Sounds Library` to assign/unassign assets to slots.
6. Use `App Routing` to assign apps to profiles.

Sample pack:

- `/Users/mikeonator/Documents/Code/MacOSTypingSounds/Examples/SampleClickPack`

## Test

```bash
xcodebuild test -project MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
```

Legacy reference hygiene check:

```bash
./Scripts/check_legacy_hygiene.sh
```

Release hardening checklist:

- `RELEASE_CHECKLIST_v3.0.0.md`
