import 'dart:io';
import 'platform.dart' if (dart.library.ui) 'platform_native.dart';
import 'package:translocale_delivery/translocale_delivery.dart';
import 'package:translocale_delivery/translocale_delivery_io.dart';

DeliveryCache createPlatformCache({String Function()? directoryProvider}) =>
    _ApplicationCache(directoryProvider ?? applicationSupportDirectory);

class _ApplicationCache implements DeliveryCache {
  _ApplicationCache(this.directoryProvider);
  final String Function() directoryProvider;
  FileDeliveryCache? _cache;

  FileDeliveryCache _open() {
    if (_cache case final cache?) return cache;
    final path = directoryProvider();
    if (path.isEmpty || !Directory(path).isAbsolute) {
      throw StateError('Use a private absolute application-support directory.');
    }
    return _cache = FileDeliveryCache(
      Directory('$path${Platform.pathSeparator}translocale-delivery'),
    );
  }

  @override
  Future<String?> read(String key) async => _open().read(key);

  @override
  Future<void> write(String key, String value) async =>
      _open().write(key, value);
}
