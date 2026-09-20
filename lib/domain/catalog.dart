import 'dart:convert';

import 'localized_text.dart';
import 'rule.dart';
import 'source_ref.dart';

/// Raised when a catalog file does not hold what the engine needs. The message
/// always names the offending rule, because a catalog is edited by hand and the
/// person fixing it needs to know where to look.
class CatalogFormatException implements Exception {
  const CatalogFormatException(this.catalogId, this.message);

  final String catalogId;
  final String message;

  @override
  String toString() => 'CatalogFormatException($catalogId): $message';
}

/// One versioned set of rules, such as the children's check-ups.
class Catalog {
  const Catalog({
    required this.id,
    required this.version,
    required this.name,
    required this.sources,
    required this.rules,
  });

  factory Catalog.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw CatalogFormatException('<unparsed>', 'invalid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const CatalogFormatException('<unparsed>', 'expected an object');
    }
    return Catalog.fromJson(decoded.cast<String, Object?>());
  }

  factory Catalog.fromJson(Map<String, Object?> json) {
    final id = json['catalogId'];
    if (id is! String || id.isEmpty) {
      throw const CatalogFormatException('<unnamed>', '"catalogId" is required');
    }
    try {
      final version = json['catalogVersion'];
      if (version is! String || version.isEmpty) {
        throw const FormatException('"catalogVersion" is required');
      }

      final rawSources = json['sources'];
      if (rawSources is! Map || rawSources.isEmpty) {
        throw const FormatException('"sources" must list at least one source');
      }
      final sources = <String, SourceRef>{
        for (final entry in rawSources.entries)
          entry.key.toString(): SourceRef.fromJson(
            entry.key.toString(),
            (entry.value as Map).cast(),
          ),
      };

      final rawRules = json['rules'];
      if (rawRules is! List || rawRules.isEmpty) {
        throw const FormatException('"rules" must be a non-empty list');
      }
      final rules = [
        for (final rule in rawRules)
          Rule.fromJson(
            (rule as Map).cast(),
            catalogId: id,
            sources: sources,
          ),
      ];
      final ids = rules.map((r) => r.id).toSet();
      if (ids.length != rules.length) {
        throw const FormatException('rule ids must be unique within a catalog');
      }

      return Catalog(
        id: id,
        version: version,
        name: LocalizedText.fromJson(json['name']),
        sources: Map.unmodifiable(sources),
        rules: List.unmodifiable(rules),
      );
    } on FormatException catch (e) {
      throw CatalogFormatException(id, e.message);
    }
  }

  final String id;

  /// Bumped whenever the rules change, and shown in the app beside the sources
  /// so a user can tell which edition they are looking at.
  final String version;

  final LocalizedText name;
  final Map<String, SourceRef> sources;
  final List<Rule> rules;

  Rule? ruleById(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }
}

/// Every catalog the app ships, treated as one rule set.
class CatalogSet {
  CatalogSet(List<Catalog> catalogs)
    : catalogs = List.unmodifiable(catalogs),
      rules = List.unmodifiable([for (final c in catalogs) ...c.rules]);

  final List<Catalog> catalogs;
  final List<Rule> rules;

  Rule? ruleById(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  Iterable<SourceRef> get sources =>
      catalogs.expand((c) => c.sources.values).toSet();
}
