# V2 QA: App Routing + Flat Import + In-App Slot Mapping

## Environment

- Date: 2026-02-23
- Project: `/Users/mikeonator/Documents/Code/MacOSTypingSounds/MacOSTypingSounds.xcodeproj`
- Scheme: `MacOSTypingSounds`
- Machine: local macOS (developer workstation)

## Build / Test Commands

- Build:
  - `xcodebuild -project /Users/mikeonator/Documents/Code/MacOSTypingSounds/MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Test:
  - `xcodebuild test -project /Users/mikeonator/Documents/Code/MacOSTypingSounds/MacOSTypingSounds.xcodeproj -scheme MacOSTypingSounds -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO`

## Automated Results (Agent Run)

- `build`: PASS
- `test`: PASS (`9` tests)

Covered in automated tests:

- OGG Vorbis import conversion to WAV
- Slot-folder importer compatibility (legacy importer methods)
- Flat recursive import leaving assets unassigned
- App rule persistence and assigned-profile lookup
- Keycode-to-slot mapping
- V2 typing-slot clear/remove semantics (allowed; fallback behavior maintained)

## Manual QA Checklist (v2)

Status values:

- `PASS`: verified manually
- `NOT RUN`: not verified in terminal-only session
- `FAIL`: verified and broken

| Scenario | Expected | Status | Notes |
|---|---|---|---|
| Preferences opens | Preferences window appears and updates labels to v2 wording | NOT RUN | Requires interactive desktop UI |
| Sound Mapping window opens | `Edit Sound Mapping…` opens mapping editor for selected profile | NOT RUN | Requires interactive desktop UI |
| App Routing window opens | `Manage App Routing…` opens app routing editor | NOT RUN | Requires interactive desktop UI |
| Flat import sample pack | Imports all audio recursively, assets initially unassigned | NOT RUN | Use `/Users/mikeonator/Documents/Code/MacOSTypingSounds/Examples/SampleClickPack` |
| Slot mapping assignment | Assign assets to slots and counts update | NOT RUN | Verify `typing`, `enter`, `launch`, `quit` at minimum |
| Multi-slot reuse | Same asset can be assigned to multiple slots | NOT RUN | Assign one file to `typing` and `enter` |
| App routing rule add (running app) | Rule saved from running app picker | NOT RUN | Test Terminal / VS Code if running |
| App routing rule add (bundle ID) | Rule saved for manual bundle ID entry | NOT RUN | Example `com.apple.Terminal` |
| Typing profile switches by frontmost app | Assigned app uses assigned profile | NOT RUN | Requires live key monitoring + app switching |
| Launch/quit sounds for assigned apps | Assigned app launch/quit uses profile slots | NOT RUN | Test Terminal / VS Code / other assigned app |
| Unassigned apps fallback behavior | Uses default profile when assigned-only is OFF | NOT RUN | Toggle menu/Preferences setting |
| Unassigned apps silent behavior | No sound when assigned-only is ON | NOT RUN | Toggle menu/Preferences setting |

## Follow-Up Notes

- The v2 backend migration keeps legacy slot folders on disk (non-destructive) and writes new assignment metadata to per-profile `profile-config.plist`.
- Existing v1 importer methods are preserved for compatibility and tests, but v2 UI is flat-import-first.
