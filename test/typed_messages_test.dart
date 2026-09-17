import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:test/test.dart';
import 'package:translocale_dartnative/src/bundle.dart';

void main() {
  late Directory root;
  void arb(String locale, Map<String, Object> values) {
    File(
      '${root.path}/arb/$locale.arb',
    ).writeAsStringSync(jsonEncode({'@@locale': locale, ...values}));
  }

  String generate({
    bool check = false,
    bool replace = false,
    String className = 'AppStrings',
  }) => generateBundle(
    directory: '${root.path}/arb',
    sourceLocale: 'en',
    catalog: 'app.arb',
    output: '${root.path}/strings.dart',
    check: check,
    replace: replace,
    className: className,
  );
  Map<String, Object> metadata(
    String type, {
    String? format,
    Map<String, Object>? options,
  }) => {
    'placeholders': {
      'value': {
        'type': type,
        if (format != null) 'format': format,
        if (options != null) 'optionalParameters': options,
      },
    },
  };
  setUp(() {
    root = Directory.systemTemp.createTempSync('typed-messages-');
    Directory('${root.path}/arb').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'rejects incomplete, weak, conflicting and unsafe source contracts before writing',
    () {
      for (final source in <Map<String, Object>>[
        {'hello': 'Hello {value}'},
        {'hello': 'Hello {value}', '@hello': metadata('Object')},
        {'hello': 'Hello {value}', '@hello': metadata('dynamic')},
        {'hello': 'Hello {value}', '@hello': metadata('String?')},
        {'hello': 'Hello {value}', '@hello': metadata('String); evil(')},
        {
          'hello': '{value, plural, one{One} other{Many}}',
          '@hello': metadata('String'),
        },
        {
          'hello': '{value, select, yes{Yes} other{No}}',
          '@hello': metadata('int'),
        },
        {'hello': '{state, select, yes{{missing}} other{No}}'},
        {'hello': 'No argument', '@hello': metadata('String')},
        {'hello': '{value}', '@hello': metadata('DateTime')},
        {
          'hello': '{value}',
          '@hello': metadata('DateTime', format: 'notASkeleton'),
        },
        {
          'hello': '{value}',
          '@hello': metadata('int', format: 'notAConstructor'),
        },
        {
          'hello': '{value}',
          '@hello': metadata(
            'double',
            format: 'currency',
            options: {'code': 'CAD'},
          ),
        },
        {
          'hello': '{value}',
          '@hello': metadata(
            'double',
            format: 'currency',
            options: {'decimalDigits': 'two'},
          ),
        },
        {'hello': '{value}', '@hello': metadata('String', format: 'currency')},
        {
          'hello': '{value, plural, other{# entries}}',
          '@hello': metadata('int'),
        },
        {
          'hello': '{value, selectordinal, other{Entry}}',
          '@hello': metadata('int'),
        },
        {
          'hello': '{value, plural, offset:1 other{Entry}}',
          '@hello': metadata('int'),
        },
      ]) {
        arb('en', source);
        expect(() => generate(), throwsFormatException, reason: '$source');
        expect(File('${root.path}/strings.dart').existsSync(), false);
      }
    },
  );

  test('rejects invalid names and duplicate decoded JSON keys', () {
    for (final key in [
      'a.b',
      'a-b',
      '_hidden',
      'class',
      'hashCode',
      'String',
      'int',
      'DateTime',
      'TransLocaleMessageResolver',
      'AppStrings',
    ]) {
      arb('en', {key: 'Hello'});
      expect(() => generate(), throwsFormatException, reason: key);
    }
    arb('en', {'hello': 'Hello'});
    expect(() => generate(className: 'String'), throwsFormatException);
    expect(() => generate(className: 'strings'), throwsFormatException);
    File(
      '${root.path}/arb/en.arb',
    ).writeAsStringSync(r'{"@@locale":"en","hello":"One","h\u0065llo":"Two"}');
    expect(() => generate(), throwsFormatException);
  });

  test('checks every target branch and preserves source types and formats', () {
    arb('en', {
      'hello': '{value}',
      '@hello': metadata('int', format: 'decimalPattern'),
    });
    for (final target in <Map<String, Object>>[
      {'hello': '{missing}'},
      {'hello': '{value, select, yes{Oui} other{Non}}'},
      {'hello': '{value}', '@hello': metadata('String')},
      {'hello': '{value}', '@hello': metadata('int', format: 'compact')},
    ]) {
      arb('fr', target);
      expect(() => generate(), throwsFormatException);
    }
    arb('fr', {
      'hello': '{value}',
      '@hello': {'description': 'A French note'},
    });
    generate();
  });

  test('metadata-only signature changes make generated code stale', () {
    arb('en', {'hello': '{value}', '@hello': metadata('String')});
    final before = generate();
    arb('en', {'hello': '{value}', '@hello': metadata('int')});
    expect(() => generate(check: true), throwsStateError);
    expect(File('${root.path}/strings.dart').readAsStringSync(), before);
    expect(generate(replace: true), contains('required int value'));
  });

  test(
    'generated consumer compiles, rejects bad calls and retains live runtime behavior',
    () async {
      arb('en', {
        'title': 'Journal',
        'hello': 'Hello {name}',
        '@hello': {
          'placeholders': {
            'name': {'type': 'String'},
          },
        },
        'items': '{value, plural, one{One entry} other{{value} entries}}',
        '@items': metadata('int', format: 'decimalPattern'),
        'date': 'Date: {value}',
        '@date': metadata('DateTime', format: 'yMd'),
        'cost': '{value}',
        '@cost': metadata(
          'double',
          format: 'currency',
          options: {'name': 'CAD', 'decimalDigits': 2},
        ),
        'fallbackDate': '{value}',
        '@fallbackDate': metadata('DateTime', format: 'yMd'),
      });
      arb('fr', {
        'title': 'Journal français',
        'hello': 'Bonjour {name}',
        'items': '{value} entrées',
        'date': 'Date : {value}',
        'cost': '{value}',
      });
      generate();
      final configUri = (await Isolate.packageConfig)!;
      final config =
          jsonDecode(File.fromUri(configUri).readAsStringSync())
              as Map<String, dynamic>;
      for (final package in config['packages'] as List) {
        package['rootUri'] = configUri
            .resolve(package['rootUri'] as String)
            .toString();
      }
      Directory('${root.path}/.dart_tool').createSync();
      File(
        '${root.path}/.dart_tool/package_config.json',
      ).writeAsStringSync(jsonEncode(config));
      File('${root.path}/valid.dart').writeAsStringSync('''
import 'strings.dart';
import 'package:translocale_dartnative/messages.dart';
import 'package:translocale_delivery/translocale_delivery.dart';
import 'package:intl/intl.dart';

class Updates implements DeliveryRuntime {
  final catalogs = <String, Map<String, String>>{};
  @override final channel = 'preview';
  @override final appVersion = '1.0.0';
  @override final state = const DeliveryState();
  @override Map<String, String>? getCatalog(String file, String locale) => catalogs[locale];
  @override String resolve(String file, String locale, String key, String fallback) => getCatalog(file, locale)?[key] ?? fallback;
  @override void Function() addListener(void Function() listener) => () {};
  @override Future<void> start() async {}
  @override Future<void> check() async {}
  @override void setActive(bool active) {}
  @override void dispose() {}
}
void equal(Object actual, Object expected) {
  if (actual != expected) throw StateError('Expected \$expected, got \$actual');
}
void main() {
  final updates = Updates();
  final controller = TransLocale(catalog: translocaleCatalog, locale: 'en', delivery: updates);
  final strings = controller.strings;
  equal(strings.title, 'Journal');
  equal(strings.hello(name: 'Sam'), 'Hello Sam');
  equal(strings.items(value: 1), 'One entry');
  equal(strings.items(value: 1200), '1,200 entries');
  final date = DateTime(2026, 9, 16);
  equal(strings.date(value: date), 'Date: \${DateFormat.yMd('en').format(date)}');
  controller.setLocale('fr');
  equal(identical(strings, controller.strings), true);
  equal(strings.hello(name: 'Sam'), 'Bonjour Sam');
  equal(strings.cost(value: 12.5), NumberFormat.currency(locale: 'fr', name: 'CAD', decimalDigits: 2).format(12.5));
  equal(strings.date(value: date), 'Date : \${DateFormat.yMd('fr').format(date)}');
  equal(strings.fallbackDate(value: date), DateFormat.yMd('en').format(date));
  updates.catalogs['fr'] = {'hello': 'Salut {name}', 'items': '{value, plural, one{Une entrée} other{{value} entrées}}'};
  equal(strings.hello(name: 'Sam'), 'Salut Sam');
  equal(strings.items(value: 1200), '\${NumberFormat.decimalPattern('fr').format(1200)} entrées');
  updates.catalogs['fr']!['hello'] = '{missing}';
  equal(strings.hello(name: 'Sam'), 'Bonjour Sam');
  updates.catalogs.clear();
  equal(strings.hello(name: 'Sam'), 'Bonjour Sam');
  controller.dispose();
  print('Typed runtime checks passed.');
}
''');
      File('${root.path}/invalid.dart').writeAsStringSync('''
import 'strings.dart';
import 'package:translocale_dartnative/messages.dart';
void main() {
  final strings = TransLocale(catalog: translocaleCatalog, locale: 'en').strings;
  strings.helo(name: 'Sam');
  strings.hello();
  strings.hello(name: 42);
  strings.items(value: '3');
}
''');
      ProcessResult run(List<String> args) => Process.runSync(
        Platform.resolvedExecutable,
        args,
        workingDirectory: root.path,
      );
      final valid = run(['analyze', 'valid.dart']);
      expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
      final invalid = run(['analyze', 'invalid.dart']);
      expect(invalid.exitCode, isNot(0));
      expect(invalid.stdout, contains('undefined_method'));
      expect(invalid.stdout, contains('missing_required_argument'));
      expect(
        'argument_type_not_assignable'.allMatches(invalid.stdout as String),
        hasLength(2),
      );
      final executed = run([
        '--packages=.dart_tool/package_config.json',
        'valid.dart',
      ]);
      expect(
        executed.exitCode,
        0,
        reason: '${executed.stdout}\n${executed.stderr}',
      );
      expect(executed.stdout, contains('Typed runtime checks passed.'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
