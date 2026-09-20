/// A piece of catalog text in every language the app ships.
///
/// Catalog text is data, not UI copy, so it lives beside its rule and its
/// source rather than in the ARB files.
class LocalizedText {
  const LocalizedText(this._byLocale);

  factory LocalizedText.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('expected an object of language codes');
    }
    final byLocale = <String, String>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('"${entry.key}" must be a non-empty string');
      }
      byLocale[entry.key.toString()] = value;
    }
    for (final locale in supportedLocales) {
      if (!byLocale.containsKey(locale)) {
        throw FormatException('missing "$locale" translation');
      }
    }
    return LocalizedText(Map.unmodifiable(byLocale));
  }

  /// Every locale a catalog entry must provide. A rule that is missing one
  /// fails catalog validation rather than falling back at runtime, because a
  /// silent fallback hides a gap until a user sees it.
  static const supportedLocales = ['en', 'de'];

  final Map<String, String> _byLocale;

  String call(String locale) => _byLocale[locale] ?? _byLocale['en']!;

  Map<String, String> get byLocale => _byLocale;

  @override
  String toString() => _byLocale['en'] ?? _byLocale.values.first;
}
