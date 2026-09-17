import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:translocale_dartnative/src/bundle.dart';

void main() {
  late Directory dir;
  late String out;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('translocale-bundle-');
    out = '${dir.path}/out.dart';
  });
  tearDown(() => dir.deleteSync(recursive: true));
  void arb(String locale, Map<String, Object> messages) => File(
    '${dir.path}/$locale.arb',
  ).writeAsStringSync(jsonEncode({'@@locale': locale, ...messages}));
  String generate({bool check = false, bool replace = false}) => generateBundle(
    directory: dir.path,
    sourceLocale: 'en',
    catalog: 'app.arb',
    output: out,
    check: check,
    replace: replace,
  );
  test(
    'bundles Unicode and escapes Dart interpolation without executing it',
    () {
      arb('en', {
        'hello': r'Hello $name ${throw Error()}',
        'quote': "it's fine",
      });
      arb('ar', {'hello': 'مرحبًا'});
      final s = generate();
      expect(s, contains(r'\$name'));
      expect(s, contains(r'\${throw Error()}'));
      expect(s, contains('مرحبًا'));
      expect(generate(check: true), s);
    },
  );
  test(
    'checks stale sources and preserves existing output until explicit replace',
    () {
      arb('en', {'hello': 'Hello'});
      final s = generate();
      expect(() => generate(), throwsStateError);
      arb('en', {'hello': 'Changed'});
      expect(() => generate(check: true), throwsStateError);
      expect(File(out).readAsStringSync(), s);
      generate(replace: true);
      expect(File(out).readAsStringSync(), contains('Changed'));
      File(out).writeAsStringSync('user file');
      expect(() => generate(replace: true), throwsStateError);
    },
  );
  test('refuses symlinked inputs and outputs', () {
    arb('en', {'hello': 'Hello'});
    Link('${dir.path}/fr.arb').createSync('${dir.path}/en.arb');
    expect(() => generate(), throwsFormatException);
    Link('${dir.path}/fr.arb').deleteSync();
    Link(out).createSync('${dir.path}/en.arb');
    expect(() => generate(), throwsA(isA<FileSystemException>()));
  });
  test('rejects missing locale, duplicate locales, and nonstring messages', () {
    File('${dir.path}/en.arb').writeAsStringSync('{"hello":"Hi"}');
    expect(() => generate(), throwsFormatException);
    arb('en', {'hello': 1});
    expect(() => generate(), throwsFormatException);
    arb('en', {'hello': 'Hi'});
    File(
      '${dir.path}/duplicate.arb',
    ).writeAsStringSync('{"@@locale":"en","hello":"Hi"}');
    expect(() => generate(), throwsFormatException);
  });
}
