# Visitor — Export & Device Testing Guide

> Target platforms: Android (APK/AAB) + iOS (IPA)
> Engine: Godot 4.x · Genre: fate_arbiter (7-night inspection loop, 7 endings)

---

## 1. Android Export

### Prerequisites
- **Godot 4.x** with Android export templates installed (Editor → Manage Export Templates)
- **Java JDK 17+** (for signing)
- **Android SDK** (command-line tools minimum)
- **Release keystore** — see `SIGNING_GUIDE.md` (create once per game, never commit it)

### Export Preset Configuration
| Setting | Value |
|--------|-------|
| Package name | `com.deeptales.visitor` |
| Minimum SDK | API 24 (Android 7.0) |
| Target SDK | API 34 (Android 14) |
| Architecture | arm64-v8a, armeabi-v7a, x86_64 |
| Export format | AAB (Play Store) or APK (testing) |
| Screen orientation | Portrait |
| | |
| **Godot settings** | |
| Renderer | `gl_compatibility` (broad device support) |
| Texture compression | ETC2 (Android standard) |

### Key preset fields (`export_presets.cfg`, Android Release preset)
```ini
package/unique_name="com.deeptales.visitor"
version/code=2            # bump EVERY Play upload (see SIGNING_GUIDE.md)
version/name="1.1.0"
keystore/release="<slug>-release.keystore"
keystore/release_user="<slug>"
```

### Testing Checklist — Android
- [ ] App installs on Android 7+ device
- [ ] App launches without black screen
- [ ] Touch controls respond (door knock/listen/examine flow, verdict buttons)
- [ ] Portrait mode displays correctly (no stretching)
- [ ] Save persists after app close AND device restart (incl. across night boundary)
- [ ] Audio: 33 cues play (knocks, ambience, CRT hum); ducks on notification
- [ ] Visitor portraits + reveal variants load without distortion
- [ ] CRT/VHS shaders render on older devices (or CRT toggle respected)
- [ ] No crashes during a full 7-night run
- [ ] Back button pauses (never quits mid-inspection)
- [ ] Memory stays under 300 MB mid-tier

---

## 2. iOS Export

### Prerequisites
- **macOS** with Xcode 15+, iOS export templates, Apple Developer account ($99/year)
- Provisioning profile + signing certificate, App ID registered

| Setting | Value |
|--------|-------|
| Bundle identifier | `com.deeptales.visitor` |
| Minimum iOS version | 14.0 |
| Renderer | `gl_compatibility` · Texture compression ASTC |
| Orientation | Portrait (match Android) |

### Testing Checklist — iOS
- [ ] Installs via TestFlight or Xcode; launches clean
- [ ] Safe area respected (notch / Dynamic Island)
- [ ] Save persists after swipe-close; audio pauses on phone call
- [ ] No crashes during a full 7-night run; memory under 200 MB

---

## 3. Common Issues & Solutions

### Black screen on launch
Missing export templates or wrong renderer → `gl_compatibility`, install mobile templates.

### iOS Release preset missing from export dialog
Duplicate `[preset.N]` numbers in `export_presets.cfg` — each preset needs a unique index (fixed in template; check hand edits).

### Save not persisting
Saves must use `user://` (app-private storage). Never `res://` — read-only on mobile.

### Audio stuttering
`.ogg` for music/ambience (streamed), `.wav` for short SFX. Visitor's 33 cues are synthesized — re-run `tools/audio_synth.py` only if you accept overwriting hand-tuned files.

### Shader effects not rendering
Test on minimum-spec devices; CRT toggle in Settings is the fallback. Avoid loops/texture sampling in fragment shaders for low-end.

---

## 4. Export Workflow

```
1. Test in Godot editor (PC) — full 7-night run
2. Export APK → install on Android test device
3. Run DEVICE_QA.md + PLAYTEST_SCRIPT.md, log in QA_LOG.md
4. Fix issues (backport engine fixes to the blueprint)
5. Export signed AAB → Play Console internal testing track
6. Beta test with 5-10 testers → fix → production
```

---

## 5. File Sizes (Estimated)

| Component | Size |
|-----------|------|
| Godot engine (Android) | ~35 MB |
| Game scripts | ~2 MB |
| Portraits (20 + 7 reveal) | ~4 MB |
| Endings / scenes art | ~3 MB |
| Audio (33 cues) | ~10-15 MB |
| Story data (JSON) | <1 MB |
| **Total APK** | **~55-60 MB** |
