import 'dart:convert';

import 'localized_text.dart';
import 'person.dart';
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

/// What one edition of a catalog changed, in the words the app shows after an
/// update brought that edition along.
class CatalogChange {
  const CatalogChange({required this.version, required this.note});

  factory CatalogChange.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('every "_changes" entry needs a "version"');
    }
    try {
      return CatalogChange(
        version: version,
        note: LocalizedText.fromJson({
          for (final entry in json.entries)
            if (entry.key != 'version') entry.key: entry.value,
        }),
      );
    } on FormatException catch (e) {
      throw FormatException('"_changes" entry for "$version": ${e.message}');
    }
  }

  final String version;
  final LocalizedText note;
}

/// One versioned set of rules, such as the children's check-ups.
class Catalog {
  const Catalog({
    required this.id,
    required this.version,
    required this.name,
    required this.sources,
    required this.rules,
    this.changes = const [],
    this.species = const {Species.human},
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
      throw const CatalogFormatException(
        '<unnamed>',
        '"catalogId" is required',
      );
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
          Rule.fromJson((rule as Map).cast(), catalogId: id, sources: sources),
      ];
      final ids = rules.map((r) => r.id).toSet();
      if (ids.length != rules.length) {
        throw const FormatException('rule ids must be unique within a catalog');
      }

      final rawChanges = json['_changes'];
      if (rawChanges != null && rawChanges is! List) {
        throw const FormatException('"_changes" must be a list');
      }
      final changes = [
        for (final change in rawChanges as List? ?? const [])
          CatalogChange.fromJson((change as Map).cast()),
      ];

      final rawSpecies = json['species'];
      if (rawSpecies != null && (rawSpecies is! List || rawSpecies.isEmpty)) {
        throw const FormatException('"species" must be a non-empty list');
      }
      final species = <Species>{
        for (final name in rawSpecies as List? ?? const ['human'])
          Species.values.firstWhere(
            (s) => s.name == name,
            orElse: () => throw FormatException('unknown species "$name"'),
          ),
      };

      return Catalog(
        id: id,
        species: Set.unmodifiable(species),
        version: version,
        name: LocalizedText.fromJson(json['name']),
        sources: Map.unmodifiable(sources),
        rules: List.unmodifiable(rules),
        changes: List.unmodifiable(changes),
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

  /// One note per edition, oldest first, from the catalog's `_changes` list.
  final List<CatalogChange> changes;

  /// Who the catalog is written for; people unless it says otherwise.
  final Set<Species> species;

  /// The note that describes this edition: the entry for [version], or the
  /// last one written when no entry names it.
  CatalogChange? get latestChange {
    for (final change in changes.reversed) {
      if (change.version == version) return change;
    }
    return changes.lastOrNull;
  }

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

  /// The rules of the catalogs written for [species].
  List<Rule> rulesFor(Species species) => [
    for (final catalog in catalogs)
      if (catalog.species.contains(species)) ...catalog.rules,
  ];

  Rule? ruleById(String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  Iterable<SourceRef> get sources =>
      catalogs.expand((c) => c.sources.values).toSet();
}
