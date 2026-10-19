# Echo

Echo is a turn-based neon puzzle game built with Flutter and Flame. Swipe to move one tile, tap to wait, and plan runs so your earlier runs (ghosts) help you press plates and open doors. Ads use Google's test IDs.

## Run the tests

```sh
flutter test
flutter analyze
```

## Build

```sh
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab
```

Release builds need network access to `plugins.gradle.org` (Flutter's Gradle tooling resolves a plugin from it); CI has it.

Without `android/key.properties` the release build is signed with the debug key, so it installs locally but cannot be uploaded to Google Play.

## Create the upload key

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (paths in `storeFile` resolve relative to `android/app/`):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Never commit the keystore or `key.properties`; both are git-ignored.

## CI secrets

The release workflow expects these repository secrets:

- `ANDROID_KEYSTORE_BASE64` (the keystore, base64-encoded)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
