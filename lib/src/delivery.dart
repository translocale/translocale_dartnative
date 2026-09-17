import 'dart:async';
import 'package:http/http.dart' as http;
import 'platform.dart' if (dart.library.ui) 'platform_native.dart';
import 'package:translocale_delivery/translocale_delivery.dart';
import 'platform_cache.dart';

/// DartNative delivery with app-version detection and platform-specific caching.
///
/// Create once and pass to the TransLocaleBuilder.
/// Initialization is deferred until [start] or [check]; construction performs no
/// platform or network work. The builder starts it after the first frame.
class DartNativeDelivery implements DeliveryRuntime {
  /// Configures read-only delivery for one project and catalog schema.
  ///
  /// [appVersion] overrides platform detection. [appVersionProvider] is useful
  /// for tests or a custom version source. An explicit [cache] takes precedence
  /// over [persistentCache]. [clientFactory] must return a fresh HTTP client;
  /// each request closes its client when finished or cancelled.
  DartNativeDelivery({
    required this.projectId,
    required this.schemaHash,
    required this._token,
    this.channel = 'production',
    this.apiBaseUrl = 'https://translocale.io',
    this._appVersion,
    Future<String> Function()? appVersionProvider,
    DeliveryCache? cache,
    bool persistentCache = true,
    String Function()? cacheDirectoryProvider,
    this.pollInterval = const Duration(minutes: 5),
    this._clientFactory,
  }) : _appVersionProvider = appVersionProvider ?? _platformVersion,
       _cache =
           cache ??
           (persistentCache
               ? createPlatformCache(directoryProvider: cacheDirectoryProvider)
               : null) {
    _state = DeliveryState(cache: _cache == null ? 'disabled' : 'empty');
  }

  /// The cloud project's UUID.
  final String projectId;

  /// The compatibility hash emitted by the generated localization adapter.
  final String schemaHash;

  /// An HTTPS service origin. Loopback HTTP is allowed for local development.
  final String apiBaseUrl;
  @override
  final String channel;

  /// Automatic refresh interval, from 30 seconds to one hour.
  final Duration pollInterval;
  String _token;
  String? _appVersion;
  Future<String> Function()? _appVersionProvider;
  DeliveryCache? _cache;
  http.Client Function()? _clientFactory;
  DeliveryClient? _client;
  late DeliveryState _state;
  final Set<void Function()> _listeners = {};
  void Function()? _unsubscribe;
  Completer<void>? _initialization, _cancelInitialization;
  bool _disposed = false, _active = true, _started = false;

  static Future<String> _platformVersion() async => await installedAppVersion();

  @override
  String? get appVersion => _client?.appVersion ?? _appVersion;

  @override
  DeliveryState get state => _client?.state ?? _state;

  @override
  String resolve(String file, String locale, String key, String fallback) =>
      _client?.resolve(file, locale, key, fallback) ?? fallback;

  @override
  Map<String, String>? getCatalog(String file, String locale) =>
      _client?.getCatalog(file, locale);

  @override
  void Function() addListener(void Function() listener) {
    if (!_disposed) _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify({bool disposing = false}) {
    for (final listener in _listeners.toList()) {
      if (_disposed && !disposing) break;
      try {
        listener();
      } catch (_) {
        // A listener cannot interrupt initialization or delivery.
      }
    }
  }

  @override
  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    if (_client case final client?) {
      client.setActive(value);
    } else if (value && _started) {
      unawaited(start());
    }
  }

  @override
  Future<void> start() => _initializeOrRefresh(refresh: false);

  @override
  Future<void> check() => _initializeOrRefresh(refresh: true);

  Future<String?> _readAppVersion(Completer<void> cancel) async {
    final expired = Completer<String?>();
    final timer = Timer(const Duration(seconds: 3), () {
      expired.completeError(TimeoutException('App version lookup timed out.'));
    });
    try {
      return await Future.any<String?>([
        Future<String>.sync(_appVersionProvider!),
        cancel.future.then((_) => null),
        expired.future,
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _initializeOrRefresh({required bool refresh}) {
    if (_disposed) return Future.value();
    if (_initialization case final pending?) return pending.future;
    if (_client case final client?) {
      return refresh ? client.check() : client.start();
    }
    _started = true;
    final done = Completer<void>(), cancel = Completer<void>();
    _initialization = done;
    _cancelInitialization = cancel;
    _state = DeliveryState(
      status: 'initializing',
      cache: _cache == null ? 'disabled' : 'empty',
    );
    _notify();
    unawaited(() async {
      var errorKind = 'app_version';
      try {
        if (_disposed) return;
        final version = _appVersion ?? await _readAppVersion(cancel);
        if (_disposed || version == null) return;
        errorKind = 'configuration';
        final client = DeliveryClient(
          projectId: projectId,
          schemaHash: schemaHash,
          token: _token,
          channel: channel,
          appVersion: version,
          apiBaseUrl: apiBaseUrl,
          cache: _cache,
          pollInterval: pollInterval,
          clientFactory: _clientFactory,
        );
        _appVersion = version;
        _client = client;
        client.setActive(_active);
        _unsubscribe = client.addListener(_notify);
        await client.start();
      } catch (_) {
        if (!_disposed) {
          _state = DeliveryState(
            status: 'error',
            error: errorKind,
            cache: _state.cache,
          );
          _notify();
        }
      } finally {
        _initialization = null;
        _cancelInitialization = null;
        done.complete();
      }
    }());
    return done.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _client?.dispose();
    _client = null;
    _token = '';
    _appVersionProvider = null;
    _clientFactory = null;
    _cache = null;
    _state = const DeliveryState(status: 'disposed');
    _cancelInitialization?.complete();
    _notify(disposing: true);
    _listeners.clear();
  }
}
