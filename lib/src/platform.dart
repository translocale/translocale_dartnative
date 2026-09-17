Future<String> installedAppVersion() async => throw UnsupportedError(
  'App-version detection requires DartNative on iOS or Android.',
);
String applicationSupportDirectory() => throw UnsupportedError(
  'Native caching requires DartNative on iOS or Android.',
);
