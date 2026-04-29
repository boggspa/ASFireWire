# Lychzord Midas Venice v16 Test Build

This private copy starts from ASFW v15 (`c4d6278`) and isolates the external-test bundle IDs from Chris's local Alesis install. The v16-lych build targets macOS 15.5+ and DriverKit 24.0+ for macOS 15.6 testing.

## Identities

- App bundle ID: `com.chrisizatt.ASFWLocal`
- Driver bundle ID: `com.chrisizatt.ASFWLocal.ASFWDriver`
- Staged app path: `/Applications/ASFWLychzord.app`
- Bundle version: `16`
- Known Venice ROM identity: vendor `0x10c73f`, model `0x000001`, text `Midas` / `Venice`

## Chris-Signed Prebuilt

If using the Chris-signed prebuilt package, unzip `ASFW.app`, move it to `/Applications/ASFWLychzord.app`, open it, and use the app's install button. macOS may show Gatekeeper or system-extension approval prompts; approve the app/extension and reboot if System Settings asks for it.

The prebuilt is signed by Chris's local Apple developer identity. Lychzord does not need a paid developer team ID for this lane. The prebuilt uses Chris's known working IDs, `com.chrisizatt.ASFWLocal` and `com.chrisizatt.ASFWLocal.ASFWDriver`, because those are the IDs with the required DriverKit/System Extension capabilities available on Chris's signing setup.

## Build And Install

This lane is only for someone with a DriverKit-capable signing setup:

```sh
./tools/lychzord/preflight.sh
export ASFW_DEVELOPMENT_TEAM=YOURTEAMID
./tools/lychzord/build_local.sh
./tools/lychzord/stage_app.sh
```

Open `/Applications/ASFWLychzord.app`, then use the app's install button. Approve the system extension in System Settings if macOS asks.

If replacing a prior test build, run:

```sh
./tools/lychzord/refresh_driver.sh
```

For a compile-only reference build that is not installable:

```sh
./tools/lychzord/build_local.sh --unsigned-reference
```

For Chris to rebuild the external-test prebuilt:

```sh
./tools/lychzord/build_local.sh --chris-prebuilt
./tools/lychzord/sign_chris_prebuilt.sh
ASFW_APP_PACKAGE_KIND=signed-prebuilt ./tools/lychzord/package_artifacts.sh
```

## Midas Behavior

The private build recognizes Midas Venice as TCAT/DICE and creates the generic DICE protocol handler for vendor `0x10c73f`.

It publishes CoreAudio immediately only when runtime DICE stream discovery returns valid nonzero input/output caps. There is no guessed F24/F32 channel fallback. If runtime caps are missing, the driver retries briefly, fails closed, and the useful output is the DICE/ROM log capture.

The supplied historical DICE files mark Venice F32 as EAP unsupported, so this pass does not rely on EAP/router registers.

## First Run Capture

After connecting the Midas and attempting install/start:

```sh
./tools/lychzord/midas_health.sh --log-window 20m
```

Send back the generated Desktop folder. The important files are:

- `local_state.txt`
- `focused_logs.txt`
- `dice_register_snapshot.txt`
- `ioreg_asfw_driver.txt`
- `ioreg_asfw_audio_nub.txt`
- `coreaudio_audio.txt`

Acceptance for the first external pass:

- only one ASFW-style system extension is active for the OHCI controller
- Midas appears in discovery as vendor `0x10c73f`
- DICE section/global/TX/RX stream logs are present
- if stream caps are valid, CoreAudio publishes the Midas device
- if audio fails, logs identify whether failure was signing/install, discovery, DICE caps, stream start, or CoreAudio publication

## Rollback

```sh
export ASFW_DEVELOPMENT_TEAM=YOURTEAMID
./tools/lychzord/rollback.sh --yes
```

If macOS keeps a stale system extension entry, reboot before another install attempt.

## Packaging

After committing private-copy changes and building if desired:

```sh
./tools/lychzord/package_artifacts.sh
```

The source package excludes `.git`, build products, user Xcode state, provisioning profiles, certificates, and local signing secrets. The signed-prebuilt app package is intended for Lychzord's first Venice smoke test.
