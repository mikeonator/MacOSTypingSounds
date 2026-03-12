# MacOSTypingSounds
Simple app that plays keystroke sounds on your computer like the terminals in Fallout 3 / NV. Also plays terminal start up / shut down sounds anytime you launch mac terminal / iterm2.

#Features and Settings
- Toggle mute 
- Toggle whether to play sounds outside terminals 
  - compatible with Cool CRT https://github.com/Swordfish90/cool-retro-term

#Installation
Requires Mac OS X 10. It hasn't been tested on any other versions but it SHOULD work run on earlier versions up to snow leopard.

- Download Xcode and open the project on there.
- Export a binary by selecting product > archive > export > export as a Mac application.
- In order to hear the sounds, you must give permissions to your exported binary under preferences > security & privacy > privacy > Accessibility (add the exported app here)

# Custom Soundpacks + App Routing (v2)

This fork now supports:

- Profile-based sound libraries
- Flat soundpack import (folder names are ignored)
- In-app slot mapping (`typing`, `enter`, `launch`, `quit`, etc.)
- App-specific profile routing by bundle identifier (exact match)
- App launch/quit sounds for assigned apps

## V2 Workflow (Flat Import + Mapping)

1. Launch the app.
2. Open the status menu and choose `Preferences…`.
3. Create or select a profile.
4. Click `Import Pack…` (creates a profile and imports audio recursively as a flat library).
5. Click `Edit Sound Mapping…` for that profile.
6. Assign imported sounds to slots (`typing`, `enter`, `backspace`, `tab`, `space`, `escape`, `launch`, `quit`).
7. Click `Manage App Routing…` and assign apps (bundle IDs) to profiles.

Example pack (still useful in v2):

- `/Users/mikeonator/Documents/Code/MacOSTypingSounds/Examples/SampleClickPack`

In v2, the folders inside that sample pack are treated as organization only. The app imports audio files recursively and you assign slots in the Sound Mapping window.

## App Routing (v2)

- Routing uses exact bundle ID matching (example: `com.apple.Terminal`, `com.microsoft.VSCode`)
- Assigned apps use their profile for:
  - typing sounds
  - app launch sound (`launch` slot)
  - app quit sound (`quit` slot)
- Unassigned apps use the selected default profile (`Default Profile (Unassigned Apps)`) unless `Play SFX in assigned apps only` is enabled

## Slot Fallbacks

- Empty key slots (`enter`, `backspace`, `tab`, `space`, `escape`) fall back to `typing`
- Empty `launch` / `quit` slots fall back to bundled power sounds
- Empty `typing` falls back to bundled typing sounds

## Supported Import Types

- `.mp3`, `.wav`, `.m4a`, `.aiff`, `.ogg` (Ogg Vorbis)

`.ogg` note:

- Ogg Vorbis files are converted to `.wav` during import
- Converted files are stored in the profile's app-managed sound library

## QA Notes

- v1 QA checklist/results: `/Users/mikeonator/Documents/Code/MacOSTypingSounds/docs/qa-v1-profiles.md`
- v2 QA checklist/results: `/Users/mikeonator/Documents/Code/MacOSTypingSounds/docs/qa-v2-app-routing.md`


# My Terminal
You can check out a photo of my terminal
[here](http://i.imgur.com/hzIx86R.png)

I'm currently using iterm2 with:

Foreground color: #29E18C

Background color: #0E2E20

Text Font: Fixedsys 20
