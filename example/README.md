# DartNative localization example

An English, French, and Arabic app with bundled wording and optional TransLocale delivery. See the [package README](../README.md) for setup and release configuration.

From this directory, generate the native hosts with your installed DartNative SDK:

```sh
dn create --empty --platforms=ios,android .
dn pub get
dart --packages=.dart_tool/package_config.json tool/bundle.dart --check
dn run
```

Use DartNative's bundled `dart` executable. Keep `lib/main.dart` when generating the hosts. For Xcode 27, set the Runner and pod deployment targets to iOS 15 or later. Set `minSdk = 26` or higher in `android/app/build.gradle.kts`. The repository keeps native hosts out of version control so each developer can generate them for the installed SDK.

Tap the language buttons to change wording. The example starts with bundled translations and makes no delivery request by default.

To enable live updates, supply the project, schema, channel, origin, and read-only token in an ignored `translocale.delivery.json` file:

```json
{
  "DELIVERY_ENABLED": true,
  "DELIVERY_PROJECT": "YOUR_PROJECT_UUID",
  "DELIVERY_SCHEMA": "YOUR_SCHEMA_HASH",
  "DELIVERY_CHANNEL": "preview",
  "DELIVERY_ORIGIN": "https://translocale.io",
  "DELIVERY_TOKEN": "YOUR_READ_ONLY_DELIVERY_TOKEN",
  "APP_LOCALE": "fr"
}
```

```sh
dn run --dart-define-from-file=translocale.delivery.json
```

Use the included `release-schema.json` with `npx translocale release-schema --file release-schema.json` to compute this app's compatibility hash. Publish a matching approved release before testing delivery. The example's source labels differ from the test fixture's delivered wording so a successful update is visible.
