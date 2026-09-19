# Signing Guide (M5-2)

How to sign a DEEPTALES game for device testing and the Play Store.
Per-game keystore; secrets NEVER enter the repo.

## Debug vs release

| | Debug | Release |
|---|---|---|
| Keystore | `keystore/debug` + `debug_user`/`debug_password` in the preset (Godot default is fine) | Your own `.keystore`, created once per game |
| Built by | `python3 tools/deploy_device.py` (one-click) | Headless export (below) or Godot editor |
| Installs | Testing only | Play Store (AAB) or sideload (APK) |

## Create the release keystore (once per game)

```bash
keytool -genkeypair -alias <slug> -keyalg RSA -keysize 2048 -validity 10000 \
  -keystore <slug>-release.keystore \
  -dname "CN=Fabio Ritzel Borges, O=Indie, C=BR"
```

Store the keystore + passwords in your local password manager, and back the
`.keystore` file up with the Drive backups. **Losing it means a new store
listing — the old app can never be updated again.**

## Wire it into export_presets.cfg

In the `Android Release (AAB)` preset options:

```ini
keystore/release="<slug>-release.keystore"
keystore/release_user="<slug>"
keystore/release_password="<password, or leave blank to be prompted>"
```

Paths are relative to the project root; keep the `.keystore` next to the
project (gitignored — never commit it).

## versionCode policy

- `version/code` is an integer that must increase with EVERY Play upload.
- `version/name` is the human semver (`1.1.0`).
- Bump both together per release; record the pair in `QA_LOG.md`'s build row.

## Build + verify the release AAB

```bash
godot --headless --export-release "Android Release (AAB)" build/android/release/<slug>.aab
jarsigner -verify build/android/release/<slug>.aab   # must say "jar verified"
```

For a sideloadable APK instead, export the `Android Debug (APK)` preset —
or temporarily switch the release preset's format; never ship a debug-signed
build to the store.

## Play App Signing

On first Play Console upload, enroll in Play App Signing: Google manages the
final signing key, your keystore becomes the *upload* key. Rotation is then
possible on request — another reason the upload keystore backup still matters.
