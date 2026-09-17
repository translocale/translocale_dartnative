import 'dart:convert';
import 'package:translocale_delivery/translocale_delivery.dart';

String dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

const _reserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

void validateIdentifier(String name, {bool member = false}) {
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(name) ||
      _reserved.contains(name) ||
      (member &&
          const {
            'String',
            'int',
            'double',
            'num',
            'DateTime',
            'TransLocaleMessageResolver',
            'hashCode',
            'runtimeType',
            'toString',
            'noSuchMethod',
          }.contains(name))) {
    throw FormatException(
      'Use a public ASCII Dart identifier that does not collide with generated members: $name.',
    );
  }
}

const _numeric = {'int', 'double', 'num'};
const _types = {'String', 'int', 'double', 'num', 'DateTime'};
const _numberOptions = <String, Map<String, String>>{
  'compact': {'explicitSign': 'bool'},
  'compactLong': {'explicitSign': 'bool'},
  'compactCurrency': {
    'name': 'String',
    'symbol': 'String',
    'decimalDigits': 'int',
  },
  'compactSimpleCurrency': {'name': 'String', 'decimalDigits': 'int'},
  'currency': {
    'name': 'String',
    'symbol': 'String',
    'decimalDigits': 'int',
    'customPattern': 'String',
  },
  'simpleCurrency': {'name': 'String', 'decimalDigits': 'int'},
  'decimalPatternDigits': {'decimalDigits': 'int'},
  'decimalPercentPattern': {'decimalDigits': 'int'},
};
const _positionalNumbers = {
  'decimalPattern',
  'percentPattern',
  'scientificPattern',
};
// intl's implemented skeletons; timezone skeletons are intentionally unsupported.
const _dateFormats = {
  'd',
  'E',
  'EEEE',
  'LLL',
  'LLLL',
  'M',
  'Md',
  'MEd',
  'MMM',
  'MMMd',
  'MMMEd',
  'MMMM',
  'MMMMd',
  'MMMMEEEEd',
  'QQQ',
  'QQQQ',
  'y',
  'yM',
  'yMd',
  'yMEd',
  'yMMM',
  'yMMMd',
  'yMMMEd',
  'yMMMM',
  'yMMMMd',
  'yMMMMEEEEd',
  'yQQQ',
  'yQQQQ',
  'H',
  'Hm',
  'Hms',
  'j',
  'jm',
  'jms',
  'm',
  'ms',
  's',
};

class MessageParameter {
  MessageParameter(this.name, Map<String, dynamic> metadata)
    : type = metadata['type'] is String ? metadata['type'] as String : '',
      format = metadata['format'],
      options = metadata['optionalParameters'],
      customDate = metadata['isCustomDateFormat'] {
    validateIdentifier(name);
    if (!_types.contains(type)) {
      throw FormatException(
        '$name needs an explicit String, int, double, num, or DateTime type.',
      );
    }
    // Validate now, before writing generated code.
    formattingExpression();
  }
  final String name, type;
  final Object? format, options, customDate;
  bool get hasFormatting => type == 'DateTime' || format != null;

  String? formattingExpression() {
    if (format != null && (format is! String || (format as String).isEmpty)) {
      throw FormatException('Invalid format for $name.');
    }
    if (customDate != null && (customDate is! bool || type != 'DateTime')) {
      throw FormatException(
        'isCustomDateFormat is only valid for DateTime: $name.',
      );
    }
    if (type == 'DateTime') {
      if (format == null || options != null) {
        throw FormatException(
          '$name needs a date format and no number options.',
        );
      }
      final pattern = format as String;
      if (customDate != true && !_dateFormats.contains(pattern)) {
        throw FormatException('Unsupported date format $pattern for $name.');
      }
      return '_intl.DateFormat(${dartString(pattern)}, _locale).format($name)';
    }
    if (format == null) {
      if (options != null) {
        throw FormatException('$name has options without a format.');
      }
      return null;
    }
    if (!_numeric.contains(type)) {
      throw FormatException('Only numeric values have number formats: $name.');
    }
    final style = format as String;
    if (_positionalNumbers.contains(style)) {
      if (options != null) {
        throw FormatException('$style does not accept optionalParameters.');
      }
      return '_intl.NumberFormat.$style(_locale).format($name)';
    }
    final allowed = _numberOptions[style];
    if (allowed == null) {
      throw FormatException('Unsupported number format $style for $name.');
    }
    if (options != null && options is! Map<String, dynamic>) {
      throw FormatException('optionalParameters must be an object for $name.');
    }
    final values = options as Map<String, dynamic>? ?? const {};
    final names = values.keys.toList()..sort();
    final arguments = <String>['locale: _locale'];
    for (final key in names) {
      final value = values[key];
      final valid = switch (allowed[key]) {
        'String' => value is String,
        'bool' => value is bool,
        'int' => value is int && value >= 0 && value <= 20,
        _ => false,
      };
      if (!valid) {
        throw FormatException('Invalid $style option $key for $name.');
      }
      arguments.add(
        '$key: ${value is String ? dartString(value) : jsonEncode(value)}',
      );
    }
    return '_intl.NumberFormat.$style(${arguments.join(', ')}).format($name)';
  }
}

class GeneratedMessage {
  GeneratedMessage(this.key, String source, Object? metadata) {
    validateIdentifier(key, member: true);
    if (metadata != null && metadata is! Map<String, dynamic>) {
      throw FormatException('Metadata for $key must be an object.');
    }
    final raw = (metadata as Map<String, dynamic>?)?['placeholders'];
    if (raw != null && raw is! Map<String, dynamic>) {
      throw FormatException('Placeholders for $key must be an object.');
    }
    final declared = raw as Map<String, dynamic>? ?? const {};
    for (final name in declared.keys.toList()..sort()) {
      final value = declared[name];
      if (value is! Map<String, dynamic>) {
        throw FormatException('Invalid $key.$name metadata.');
      }
      parameters.add(MessageParameter(name, value));
    }
    validate(source);
  }
  final String key;
  final parameters = <MessageParameter>[];

  void validate(String message) {
    final used = FlutterMessageFormatter.parameters(message);
    final declared = {
      for (final parameter in parameters) parameter.name: parameter.type,
    };
    if (used.length != declared.length ||
        used.keys.any((name) => !declared.containsKey(name))) {
      throw FormatException(
        '$key must declare exactly its message placeholders with explicit types.',
      );
    }
    for (final entry in used.entries) {
      if ((entry.value == MessageParameterKind.plural &&
              !_numeric.contains(declared[entry.key])) ||
          (entry.value == MessageParameterKind.select &&
              declared[entry.key] != 'String')) {
        throw FormatException(
          'The selector ${entry.key} in $key conflicts with its declared type.',
        );
      }
    }
  }

  String emit() {
    if (parameters.isEmpty) {
      return '  String get $key => _messages.resolve(${dartString(key)});';
    }
    final signature = parameters
        .map((p) => 'required ${p.type} ${p.name}')
        .join(', ');
    final arguments = parameters
        .map((p) => '${dartString(p.name)}: ${p.name}')
        .join(', ');
    final formatted = parameters
        .where((p) => p.hasFormatting)
        .map((p) => '${dartString(p.name)}: ${p.formattingExpression()}')
        .join(', ');
    return '''  String $key({$signature}) => _messages.resolve(
    ${dartString(key)},
    arguments: {$arguments},
${formatted.isEmpty ? '' : '    formatArguments: (_locale) => {$formatted},\n'}  );''';
  }
}
