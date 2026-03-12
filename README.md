# MacOSTypingSounds

Mac menu bar app that plays keyboard and app event sounds with profile-based routing.

## What It Does

- Plays typing sounds from a selected/default profile.
- Supports per-app profile routing by bundle identifier.
- Plays assigned profile sounds for app launch and app quit events.
- Lets you run in two modes:
  - `Play SFX in all apps` (unassigned apps use default profile)
  - `Play SFX in assigned apps only` (unassigned apps are silent)
- Supports profile management (create, duplicate, rename, delete).
- Supports flat soundpack import (recursive import; folder names are ignored).
- Supports in-app slot mapping:
  - `typing`, `enter`, `backspace`, `tab`, `space`, `escape`, `launch`, `quit`

## Sound Import Support

- Supported file types: `.mp3`, `.wav`, `.m4a`, `.aiff`, `.ogg`
- `.ogg` files are converted to `.wav` on import and stored in the profile library.

## Slot Fallback Behavior

- Empty key slots (`enter`, `backspace`, `tab`, `space`, `escape`) fall back to `typing`.
- Empty `launch` / `quit` fall back to bundled power sounds.
- Empty `typing` falls back to bundled typing sounds.

## Permissions

For global keyboard/event behavior, grant the app:

- Accessibility
- Input Monitoring

You can request these from the app menu (`Request Keyboard Access…`) or in macOS Privacy & Security settings.

## Build And Run

### Xcode

1. Open `MacOSTypingSounds.xcodeproj`.
2. Build/run the `MacOSTypingSounds` scheme.

### CLI

```bash
xcodebuild -project MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Quick Usage Flow

1. Launch the app.
2. Open menu bar item -> `Preferences…`.
3. Create/select a profile.
4. Import a pack (`Import Pack…`) or add files.
5. Open `Edit Sound Mapping…` and assign assets to slots.
6. Open `Manage App Routing…` and assign apps to profiles.

Sample pack:

- `/Users/mikeonator/Documents/Code/MacOSTypingSounds/Examples/SampleClickPack`

## Test

```bash
xcodebuild test -project MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
```
