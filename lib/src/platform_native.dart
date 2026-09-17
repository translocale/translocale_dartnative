import 'package:dartnative_system/dartnative_system.dart';
import 'package:dartnative_path_provider/dartnative_path_provider.dart';

Future<String> installedAppVersion() async =>
    (await PackageInfo.fromPlatform()).version;
String applicationSupportDirectory() => getApplicationSupportDirectory();
