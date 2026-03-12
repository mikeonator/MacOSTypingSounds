# Test Fixtures

## `typing_sample.ogg`

Synthetic Ogg Vorbis tone used by `MacOSTypingSoundsTests` to verify `.ogg` import-time conversion to `.wav`.

The fixture is intentionally tiny and not game audio.

Generation command (run from repo root):

```bash
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=1280:sample_rate=22050:duration=0.045" \
  -ac 2 -ar 22050 \
  -af "volume=0.18" \
  -c:a vorbis -strict -2 -q:a 2 \
  MacOSTypingSoundsTests/Fixtures/Ogg/typing_sample.ogg
```

Note: this local `ffmpeg` build exposes the native Vorbis encoder (`vorbis`) as experimental, so `-strict -2` is required.
