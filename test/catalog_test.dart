import 'package:translocale_dartnative/src/messages.dart';
import 'package:test/test.dart';
import 'package:translocale_dartnative/src/catalog.dart';
import 'package:translocale_dartnative/src/controller.dart';
import 'package:translocale_delivery/translocale_delivery.dart';

class FakeDelivery implements DeliveryRuntime {
  Map<String, Map<String, String>> catalogs = {};
  final listeners = <void Function()>[];
  bool disposed = false;
  @override
  final String channel = 'preview', appVersion = '1.0.0';
  @override
  DeliveryState state = const DeliveryState();
  @override
  void Function() addListener(void Function() listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void notify() {
    for (final fn in listeners.toList()) {
      fn();
    }
  }

  @override
  Map<String, String>? getCatalog(String file, String locale) =>
      catalogs['$file:$locale'];
  @override
  String resolve(String file, String locale, String key, String fallback) =>
      getCatalog(file, locale)?[key] ?? fallback;
  @override
  Future<void> start() async {}
  @override
  Future<void> check() async {}
  @override
  void setActive(bool value) {}
  @override
  void dispose() {
    disposed = true;
    listeners.clear();
  }
}

void main() {
  TransLocaleCatalog<TransLocaleMessageResolver> catalog() =>
      TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: 'app.arb',
        messages: {
          'en': {
            'hello': 'Hello {name}',
            'count': '{n, plural, one{One entry} other{{n} entries}}',
            'source': 'Source',
          },
          'fr': {'hello': 'Bonjour {name}'},
          'ar': {'hello': 'مرحبًا {name}'},
          'ar-Latn': {},
          'zh-Hant': {},
        },
      );
  test('catalogs are immutable snapshots, including nested maps', () {
    final source = {
      'en': {'hello': 'Hello'},
    };
    final c = TransLocaleCatalog(
      createMessages: (resolver) => resolver,
      sourceLocale: 'en',
      file: 'app.arb',
      messages: source,
    );
    source['en']!['hello'] = 'Changed';
    expect(c.messages['en']!['hello'], 'Hello');
    expect(() => c.messages['en']!['hello'] = 'No', throwsUnsupportedError);
  });
  test(
    'locale selection uses exact then parent then source without mixing regions',
    () {
      final c = catalog();
      expect(c.resolveLocale('fr_CA'), 'fr');
      expect(c.resolveLocale('zh-Hant-TW'), 'zh-Hant');
      expect(c.resolveLocale('de-DE'), 'en');
      expect(c.resolveLocale('ar-Latn'), 'ar-Latn');
      expect(() => c.resolveLocale('../fr'), throwsArgumentError);
    },
  );
  test('rejects duplicate normalized locales and invalid catalogs', () {
    expect(
      () => TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: 'app.arb',
        messages: {
          'en': {'x': 'x'},
          'fr_CA': {},
          'fr-CA': {},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: '../app.arb',
        messages: {
          'en': {'x': 'x'},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: 'app.arb',
        messages: {
          'fr': {'x': 'x'},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: 'app.arb',
        messages: {
          'en': {'x': 'x'},
          'fr': {'y': 'y'},
        },
      ),
      throwsArgumentError,
    );
  });
  test(
    'bundled target and source fallback format placeholders and plurals',
    () {
      final t = TransLocale(catalog: catalog(), locale: 'fr');
      expect(t.resolve('hello', arguments: {'name': 'Sam'}), 'Bonjour Sam');
      expect(t.resolve('count', arguments: {'n': 1}), 'One entry');
      expect(t.resolve('count', arguments: {'n': 3}), '3 entries');
      expect(t.resolve('source'), 'Source');
      expect(t.resolve('unknown', fallback: 'Fallback'), 'Fallback');
      expect(t.resolve('hello'), 'hello');
      t.dispose();
    },
  );
  test(
    'delivery uses exact catalog/locale and malformed updates retain bundled wording',
    () {
      final d = FakeDelivery()
        ..catalogs = {
          'app.arb:fr': {'hello': 'Salut {name}'},
          'app.arb:ar': {'hello': '{bad, plural, one{oops}}'},
        };
      final t = TransLocale(catalog: catalog(), locale: 'fr-CA', delivery: d);
      expect(t.resolve('hello', arguments: {'name': 'Sam'}), 'Salut Sam');
      d.catalogs['app.arb:fr']!['hello'] = '{missing}';
      expect(t.resolve('hello', arguments: {'name': 'Sam'}), 'Bonjour Sam');
      t.setLocale('ar');
      expect(t.resolve('hello', arguments: {'name': 'Sam'}), 'مرحبًا Sam');
      t.dispose();
    },
  );
  test(
    'language changes and delivery updates notify; unsubscribe and dispose stop updates',
    () {
      final d = FakeDelivery();
      final t = TransLocale(catalog: catalog(), locale: 'en', delivery: d);
      var updates = 0;
      t.addListener(() => throw StateError('bad listener'));
      final remove = t.addListener(() => updates++);
      t.setLocale('fr');
      t.setLocale('fr');
      d.notify();
      expect(updates, 2);
      expect(t.revision, 2);
      remove();
      d.notify();
      expect(updates, 2);
      t.dispose();
      expect(d.disposed, isTrue);
      expect(d.listeners, isEmpty);
      expect(t.resolve('hello', arguments: {'name': 'Sam'}), 'Bonjour Sam');
      expect(() => t.setLocale('en'), throwsStateError);
    },
  );
  test('direction follows resolved language and explicit script', () {
    final t = TransLocale(catalog: catalog(), locale: 'ar');
    expect(t.isRightToLeft, isTrue);
    t.setLocale('ar-Latn');
    expect(t.isRightToLeft, isFalse);
    t.setLocale('fr');
    expect(t.isRightToLeft, isFalse);
  });
  test('Arabic plural branches use the selected locale', () {
    final t = TransLocale(
      catalog: TransLocaleCatalog(
        createMessages: (resolver) => resolver,
        sourceLocale: 'en',
        file: 'app.arb',
        messages: {
          'en': {'n': '{n, plural, one{one} other{other}}'},
          'ar': {
            'n':
                '{n, plural, zero{zero} one{one} two{two} few{few} many{many} other{other}}',
          },
        },
      ),
      locale: 'ar',
    );
    for (final entry in {
      0: 'zero',
      1: 'one',
      2: 'two',
      3: 'few',
      11: 'many',
      100: 'other',
    }.entries) {
      expect(t.resolve('n', arguments: {'n': entry.key}), entry.value);
    }
  });
}
