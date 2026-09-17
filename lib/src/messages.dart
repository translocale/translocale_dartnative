/// The runtime boundary used by generated message accessors.
/// Application code reads its generated strings instead of calling this API.
abstract interface class TransLocaleMessageResolver {
  String resolve(
    String key, {
    Map<String, Object> arguments = const {},
    Map<String, String> Function(String locale)? formatArguments,
    String? fallback,
  });
}
