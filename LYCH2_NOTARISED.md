# ASFireWire Lych2 Notarised Build

This copy starts from `asfw-v15-alesis-logic-clean-20260429` and prepares a v16 Developer ID/notarised app for Lychzord's Midas Venice test.

## Identity And Compatibility

- App bundle ID: `com.chrisizatt.ASFWLocal`
- Driver bundle ID: `com.chrisizatt.ASFWLocal.ASFWDriver`
- Bundle version: `16`
- macOS minimum: `15.5`
- DriverKit minimum: `24.0`
- Release app name: `ASFWLych2Notarised.app`

## Required Apple Assets

Create Developer ID distribution provisioning profiles for both bundle IDs. The profiles must not contain `get-task-allow`, and must not be limited to registered devices.

The app identifier/profile must include:

- `com.apple.developer.system-extension.install`
- `com.apple.developer.driverkit.userclient-access`

`com.apple.developer.driverkit.userclient-access` is not produced by the self-service DriverKit Communicates with Drivers checkbox. Request DriverKit UserClient Access from Apple through the System Extension / DriverKit entitlement request flow, and list the driver bundle identifier:

- `com.chrisizatt.ASFWLocal.ASFWDriver`

Do not substitute DriverKit Communicates with Drivers or DriverKit Allow Third Party UserClients for this macOS app entitlement.

The driver identifier/profile must have these capabilities enabled in the Apple Developer portal, even if the downloaded profile's CMS `Entitlements` dictionary only lists the app identifier and team:

- `com.apple.developer.driverkit`
- `com.apple.developer.driverkit.family.audio`
- `com.apple.developer.driverkit.transport.pci`

Store notary credentials once:

```sh
xcrun notarytool store-credentials asfw-notary --team-id 8CZML8FK2D
```

## Build Flow

```sh
./tools/lych2/preflight.sh
./tools/lych2/build_release.sh
./tools/lych2/sign_release.sh
./tools/lych2/notarise_release.sh
```

If profiles are not in Xcode's default profile folders, pass them explicitly:

```sh
ASFW_APP_PROFILE=/path/to/app.provisionprofile \
ASFW_DRIVER_PROFILE=/path/to/driver.provisionprofile \
./tools/lych2/sign_release.sh
```

## Lychzord First Run

Delete any ad-hoc-resigned copy first. Unzip the notarised package and open the app normally. Do not run:

```sh
codesign --force --deep --sign -
```

That command removes the `com.apple.developer.system-extension.install` entitlement and makes driver installation fail.
