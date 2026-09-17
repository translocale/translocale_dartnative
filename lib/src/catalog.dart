/// Canonicalize common BCP 47 tags used by TransLocale catalogs.
String canonicalLocale(String value) {
  final parts = value.replaceAll('_', '-').split('-');
  if (!RegExp(r'^[A-Za-z]{2,8}$').hasMatch(parts.first) ||
      parts.skip(1).any((p) => !RegExp(r'^[A-Za-z0-9]{2,8}$').hasMatch(p)) ||
      value.length > 35) {
    throw ArgumentError.value(
      value,
      'locale',
      'Use a language tag such as fr-CA.',
    );
  }
  return [
    parts.first.toLowerCase(),
    for (final part in parts.skip(1))
      if (part.length == 4)
        '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}'
      else if (part.length == 2 || RegExp(r'^\d{3}$').hasMatch(part))
        part.toUpperCase()
      else
        part.toLowerCase(),
  ].join('-');
}

/// An immutable bundled ARB catalog. Message strings use the supported ICU dialect.
class TransLocaleCatalog {
  TransLocaleCatalog({
    required String sourceLocale,
    required this.file,
    required Map<String, Map<String, String>> messages,
  }) : sourceLocale = canonicalLocale(sourceLocale),
       messages = _freeze(messages) {
    if (file.isEmpty ||
        file.length > 200 ||
        file.contains(r'\') ||
        RegExp(r'[\x00-\x1f]').hasMatch(file) ||
        file
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw ArgumentError.value(
        file,
        'file',
        'Use the cloud catalog identity.',
      );
    }
    final source = this.messages[this.sourceLocale];
    if (source == null || source.isEmpty || source.length > 200) {
      throw ArgumentError('Include a source catalog with 1–200 messages.');
    }
    if (this.messages.length > 11) {
      throw ArgumentError('Use at most ten target languages.');
    }
    for (final catalog in this.messages.values) {
      if (catalog.keys.any((key) => !source.containsKey(key))) {
        throw ArgumentError(
          'Bundled translations must use source message keys.',
        );
      }
    }
  }

  final String sourceLocale;
  final String file;
  final Map<String, Map<String, String>> messages;
  List<String> get supportedLocales => List.unmodifiable(messages.keys);

  static Map<String, Map<String, String>> _freeze(
    Map<String, Map<String, String>> input,
  ) {
    final output = <String, Map<String, String>>{};
    for (final entry in input.entries) {
      final locale = canonicalLocale(entry.key);
      if (output.containsKey(locale)) {
        throw ArgumentError('Duplicate locale: $locale.');
      }
      if (entry.value.entries.any(
        (m) =>
            m.key.isEmpty ||
            m.key.startsWith('@') ||
            m.key.length > 2000 ||
            m.value.length > 100000 ||
            const {'__proto__', 'constructor', 'prototype'}.contains(m.key),
      )) {
        throw ArgumentError(
          'Use ARB message keys and bounded message strings.',
        );
      }
      output[locale] = Map.unmodifiable(entry.value);
    }
    return Map.unmodifiable(output);
  }

  /// Resolve exact locale, then parent tags, then the bundled source locale.
  String resolveLocale(String requested) {
    var candidate = canonicalLocale(requested);
    while (true) {
      if (messages.containsKey(candidate)) return candidate;
      final separator = candidate.lastIndexOf('-');
      if (separator < 0) return sourceLocale;
      candidate = candidate.substring(0, separator);
    }
  }
}
