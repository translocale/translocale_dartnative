import 'package:translocale_delivery/translocale_delivery.dart';
import 'catalog.dart';
import 'messages.dart';

/// Owns one optional delivery runtime and the app's selected language.
/// No network or platform work occurs until start/check is called by the app or builder.
class TransLocale<T extends Object> implements TransLocaleMessageResolver {
  TransLocale({required this.catalog, required String locale, this.delivery})
    : _locale = catalog.resolveLocale(locale) {
    _unsubscribe = delivery?.addListener(_notify);
  }

  final TransLocaleCatalog<T> catalog;
  late final T strings = catalog.createMessages(this);
  final DeliveryRuntime? delivery;
  final _formatter = FlutterMessageFormatter();
  final Set<void Function()> _listeners = {};
  void Function()? _unsubscribe;
  String _locale;
  bool _disposed = false;
  int _revision = 0;
  String get locale => _locale;
  int get revision => _revision;
  List<String> get supportedLocales => catalog.supportedLocales;
  DeliveryState get state => delivery?.state ?? const DeliveryState();
  bool get isRightToLeft {
    final parts = _locale.split('-');
    // An explicit script takes precedence over the language default.
    final script = parts.where((p) => p.length == 4).firstOrNull;
    if (script != null) {
      return const {
        'Arab',
        'Hebr',
        'Thaa',
        'Nkoo',
        'Adlm',
        'Syrc',
      }.contains(script);
    }
    return const {
      'ar',
      'fa',
      'he',
      'ur',
      'ps',
      'dv',
      'yi',
      'ug',
      'sd',
    }.contains(parts.first);
  }

  void setLocale(String value) {
    if (_disposed) throw StateError('TransLocale has been disposed.');
    final next = catalog.resolveLocale(value);
    if (next == _locale) return;
    _locale = next;
    _notify();
  }

  /// Format a delivered message, then bundled target/source wording on failure.
  /// Unknown keys and unusable bundled messages return [fallback] or the key.
  /// Formatting uses the locale of each candidate, including the source fallback.
  @override
  String resolve(
    String key, {
    Map<String, Object> arguments = const {},
    Map<String, String> Function(String locale)? formatArguments,
    String? fallback,
  }) {
    final source = catalog.messages[catalog.sourceLocale]![key];
    if (source == null) return fallback ?? key;
    String format(String? message, String locale, String Function() fallback) {
      if (message == null) return fallback();
      try {
        return _formatter.format(
          message,
          locale: locale,
          arguments: arguments,
          formatted: formatArguments?.call(locale) ?? const {},
          fallback: fallback,
        );
      } catch (_) {
        return fallback();
      }
    }

    String sourceFallback() =>
        format(source, catalog.sourceLocale, () => fallback ?? key);
    String bundled() =>
        format(catalog.messages[_locale]?[key], _locale, sourceFallback);
    if (_disposed) return bundled();
    return format(
      delivery?.getCatalog(catalog.file, _locale)?[key],
      _locale,
      bundled,
    );
  }

  void Function() addListener(void Function() listener) {
    if (!_disposed) _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    if (_disposed) return;
    _revision++;
    for (final listener in _listeners.toList()) {
      if (_disposed) break;
      try {
        listener();
      } catch (_) {
        /* One listener cannot block other consumers. */
      }
    }
  }

  Future<void> start() async {
    if (!_disposed) await delivery?.start();
  }

  Future<void> check() async {
    if (!_disposed) await delivery?.check();
  }

  void setActive(bool active) {
    if (!_disposed) delivery?.setActive(active);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    delivery?.dispose();
    _listeners.clear();
    _formatter.clear();
  }
}
