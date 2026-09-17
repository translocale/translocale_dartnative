import 'dart:convert';
import 'dart:io';
import 'catalog.dart';
import 'message_codegen.dart';

/// Read ARB files and produce a Dart bundle without cloud requests or credentials.
/// All files must be regular files. Existing output is preserved unless it is
/// this generator's output and the caller explicitly passes replace.
String generateBundle({
  required String directory,
  required String sourceLocale,
  required String catalog,
  required String output,
  String className = 'AppStrings',
  bool check = false,
  bool replace = false,
}) {
  validateIdentifier(className, member: true);
  if (!RegExp(r'^[A-Z]').hasMatch(className) ||
      const {
        'String',
        'Object',
        'DateTime',
        'TransLocaleCatalog',
        'TransLocaleMessageResolver',
      }.contains(className)) {
    throw FormatException('Use a distinct PascalCase message class name.');
  }
  final dir = Directory(directory);
  final files = dir.listSync().where((f) => f.path.endsWith('.arb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty || files.length > 11) {
    throw FormatException('Use 1–11 ARB files.');
  }
  final messages = <String, Map<String, String>>{};
  final documents = <String, Map<String, dynamic>>{};
  for (final entity in files) {
    if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException(
        'ARB inputs must be regular files, not symbolic links.',
      );
    }
    final file = File(entity.path);
    if (file.lengthSync() > 100000) {
      throw FormatException('ARB inputs must be at most 100 KB.');
    }
    final json = _readArb(file.readAsStringSync());
    if (json['@@locale'] is! String) {
      throw FormatException('Every ARB file needs an @@locale string.');
    }
    final locale = canonicalLocale(json['@@locale'] as String);
    if (messages.containsKey(locale)) {
      throw FormatException('Duplicate locale: $locale.');
    }
    final entries = <String, String>{};
    for (final entry in json.entries) {
      if (entry.key.startsWith('@')) continue;
      if (entry.value is! String) {
        throw FormatException('ARB messages must be strings.');
      }
      entries[entry.key] = entry.value as String;
    }
    messages[locale] = entries;
    documents[locale] = json;
  }
  final bundled = TransLocaleCatalog(
    sourceLocale: sourceLocale,
    file: catalog,
    messages: messages,
    createMessages: (resolver) => resolver,
  );
  final source = documents[bundled.sourceLocale]!;
  final keys = bundled.messages[bundled.sourceLocale]!.keys.toList()..sort();
  final accessors = <GeneratedMessage>[];
  for (final key in keys) {
    if (key == className) {
      throw FormatException(
        'Message $key conflicts with the generated class name.',
      );
    }
    try {
      final accessor = GeneratedMessage(
        key,
        source[key] as String,
        source['@$key'],
      );
      for (final locale in bundled.supportedLocales) {
        final message = bundled.messages[locale]![key];
        if (message == null) continue;
        accessor.validate(message);
        final metadata = documents[locale]!['@$key'];
        if (metadata != null && metadata is! Map<String, dynamic>) {
          throw FormatException('$locale metadata must be an object.');
        }
        if (metadata is Map<String, dynamic> &&
            metadata.containsKey('placeholders')) {
          final translated = GeneratedMessage(key, message, metadata);
          if (translated.emit() != accessor.emit()) {
            throw FormatException(
              '$locale changes source placeholder types or formats.',
            );
          }
        }
      }
      accessors.add(accessor);
    } on FormatException catch (error) {
      throw FormatException('$key: ${error.message}');
    }
  }
  final hasDates = accessors.any(
    (m) => m.parameters.any((p) => p.type == 'DateTime'),
  );
  final hasFormatting = accessors.any(
    (m) => m.parameters.any((p) => p.hasFormatting),
  );
  final locales = bundled.supportedLocales.toList()..sort();
  final buffer = StringBuffer(_header)
    ..writeln("import 'package:translocale_dartnative/messages.dart';")
    ..write(
      hasFormatting
          ? "import 'package:translocale_dartnative/formatting.dart' as _intl;\n"
          : '',
    )
    ..writeln('')
    ..writeln('final translocaleCatalog = TransLocaleCatalog<$className>(')
    ..writeln('  createMessages: $className._,')
    ..writeln('  sourceLocale: ${dartString(bundled.sourceLocale)},')
    ..writeln('  file: ${dartString(catalog)},')
    ..writeln('  messages: {');
  for (final locale in locales) {
    buffer.writeln('    ${dartString(locale)}: {');
    final keys = bundled.messages[locale]!.keys.toList()..sort();
    for (final key in keys) {
      buffer.writeln(
        '      ${dartString(key)}: ${dartString(bundled.messages[locale]![key]!)},',
      );
    }
    buffer.writeln('    },');
  }
  buffer.writeln('  },\n);\n');
  buffer.writeln('''
final class $className {
  $className._(this._messages)${hasDates ? ' {\n    _intl.initializeMessageDates();\n  }' : ';'}
  final TransLocaleMessageResolver _messages;

${accessors.map((m) => m.emit()).join('\n\n')}
}
''');
  final content = buffer.toString();
  final target = File(output);
  final type = FileSystemEntity.typeSync(output, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException('Output must be a regular file.', output);
  }
  if (check) {
    if (!target.existsSync() || target.readAsStringSync() != content) {
      throw StateError('Bundle is stale. Regenerate it from the ARB files.');
    }
    return content;
  }
  if (target.existsSync() &&
      (!replace || !target.readAsStringSync().startsWith(_header))) {
    throw StateError(
      'Output exists. Use --replace only for a TransLocale-generated bundle.',
    );
  }
  target.parent.createSync(recursive: true);
  // A temporary sibling prevents a partially written generated Dart file.
  final temporary = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    temporary.writeAsStringSync(content, flush: true);
    temporary.renameSync(target.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
  return content;
}

const _header =
    '// Generated by translocale_dartnative. Do not edit or format.\n';

// jsonDecode accepts duplicate keys. Reject them before they can silently
// change a source signature or a formatting option.
Map<String, dynamic> _readArb(String content) {
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('An ARB catalog must be an object.');
  }
  final scopes = <Set<String>?>[];
  for (var i = 0; i < content.length; i++) {
    final char = content[i];
    if (char == '{' || char == '[') {
      scopes.add(char == '{' ? <String>{} : null);
      if (scopes.length > 32) {
        throw FormatException('ARB nesting exceeds 32 levels.');
      }
    } else if (char == '}' || char == ']') {
      scopes.removeLast();
    } else if (char == '"') {
      final start = i;
      for (i++; i < content.length; i++) {
        if (content[i] == r'\') {
          i++;
          continue;
        }
        if (content[i] == '"') break;
      }
      var next = i + 1;
      while (next < content.length && ' \r\n\t'.contains(content[next])) {
        next++;
      }
      if (next < content.length && content[next] == ':') {
        final key = jsonDecode(content.substring(start, i + 1)) as String;
        if (scopes.last?.add(key) != true) {
          throw FormatException('Duplicate ARB key: $key.');
        }
      }
    }
  }
  return decoded;
}
