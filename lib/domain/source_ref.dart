import 'localized_text.dart';

/// Where a rule comes from, shown in the app next to the appointment it backs.
class SourceRef {
  const SourceRef({
    required this.id,
    required this.name,
    required this.url,
    required this.asOf,
    this.document,
  });

  factory SourceRef.fromJson(String id, Map<String, Object?> json) {
    final url = json['url'];
    if (url is! String || !url.startsWith('https://')) {
      throw FormatException('source "$id": "url" must be an https URL');
    }
    final asOf = json['asOf'];
    if (asOf is! String) {
      throw FormatException('source "$id": "asOf" must be a date');
    }
    final parsed = DateTime.tryParse(asOf);
    if (parsed == null) {
      throw FormatException('source "$id": "asOf" is not a valid date: $asOf');
    }
    try {
      return SourceRef(
        id: id,
        name: LocalizedText.fromJson(json['name']),
        url: url,
        asOf: DateTime.utc(parsed.year, parsed.month, parsed.day),
        document: json['document'] as String?,
      );
    } on FormatException catch (e) {
      throw FormatException('source "$id": ${e.message}');
    }
  }

  final String id;
  final LocalizedText name;
  final String url;

  /// The date the document was last reviewed by a human. Shown in the app so a
  /// stale catalog is visible rather than merely wrong.
  final DateTime asOf;

  /// An optional narrower citation within the document, such as a section.
  final String? document;

  @override
  String toString() => 'SourceRef($id)';
}
