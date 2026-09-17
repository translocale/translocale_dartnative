import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:translocale_dartnative/src/delivery.dart';

void main() {
  final first =
      (jsonDecode(File('test/fixtures/releases.json').readAsStringSync())
              as Map)['first']
          as Map;
  late Directory directory;
  late List<DartNativeDelivery> clients;
  var requests = 0, versionReads = 0, cacheReads = 0;
  var offline = false;
  DartNativeDelivery make({
    Future<String> Function()? versionProvider,
    String? appVersion,
    bool persistentCache = false,
  }) {
    final c = DartNativeDelivery(
      projectId: first['projectId'],
      schemaHash: first['schemaHash'],
      token: 'tld_${'a' * 64}',
      appVersion: appVersion,
      appVersionProvider:
          versionProvider ??
          () async {
            versionReads++;
            return '1.2.3';
          },
      persistentCache: persistentCache,
      cacheDirectoryProvider: () {
        cacheReads++;
        return directory.path;
      },
      clientFactory: () => MockClient((r) async {
        requests++;
        if (offline) throw SocketException('Offline');
        return http.Response(
          jsonEncode(first),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    clients.add(c);
    return c;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'translocale-native-cache-',
    );
    clients = [];
    requests = 0;
    versionReads = 0;
    cacheReads = 0;
    offline = false;
  });
  tearDown(() async {
    for (final c in clients) {
      c.dispose();
    }
    await Future<void>.delayed(Duration(milliseconds: 30));
    directory.deleteSync(recursive: true);
  });
  test(
    'construction defers native/network work and startup coalesces checks',
    () async {
      final c = make(persistentCache: true);
      expect(versionReads, 0);
      expect(cacheReads, 0);
      expect(requests, 0);
      final pending = c.start();
      expect(identical(pending, c.check()), isTrue);
      await pending;
      expect(versionReads, 1);
      expect(cacheReads, 1);
      expect(requests, 1);
      expect(c.state.source, 'network');
    },
  );
  test('explicit version bypasses native version lookup', () async {
    final c = make(appVersion: '1.2.3');
    await c.start();
    expect(versionReads, 0);
    expect(c.appVersion, '1.2.3');
  });
  test('version failure retains fallback and permits retry', () async {
    var fail = true;
    final c = make(
      versionProvider: () async {
        if (fail) throw StateError('No metadata');
        return '1.2.3';
      },
    );
    await c.start();
    expect(c.state.error, 'app_version');
    expect(requests, 0);
    expect(c.resolve('app.arb', 'fr', 'hello', 'Fallback'), 'Fallback');
    fail = false;
    await c.check();
    expect(c.state.source, 'network');
  });
  test('dispose during version lookup cannot start delivery', () async {
    final version = Completer<String>();
    final c = make(versionProvider: () => version.future);
    final pending = c.start();
    c.dispose();
    await pending;
    version.complete('1.2.3');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    expect(c.state.status, 'disposed');
  });
  test('version lookup deadline is bounded', () {
    fakeAsync((async) {
      final c = make(versionProvider: () => Completer<String>().future);
      c.start();
      async.elapse(Duration(seconds: 4));
      expect(c.state.error, 'app_version');
      expect(requests, 0);
    });
  });
  test('native file cache restores wording on an offline restart', () async {
    final c = make(persistentCache: true);
    await c.start();
    for (var i = 0; i < 50 && c.state.cache != 'ready'; i++) {
      await Future<void>.delayed(Duration(milliseconds: 10));
    }
    expect(c.state.cache, 'ready');
    final wording = c.resolve('app.arb', 'fr', 'hello', 'Fallback');
    expect(wording, isNot('Fallback'));
    c.dispose();
    offline = true;
    final second = make(persistentCache: true);
    await second.start();
    expect(second.state.source, 'cache');
    expect(second.resolve('app.arb', 'fr', 'hello', 'Fallback'), wording);
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      expect(file.readAsStringSync(), isNot(contains('tld_')));
    }
  });
}
