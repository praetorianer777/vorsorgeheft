import 'age_offset.dart';
import 'localized_text.dart';
import 'person.dart';
import 'schedule.dart';
import 'source_ref.dart';

/// Which people a rule can apply to at all.
class Eligibility {
  const Eligibility({this.sex, this.minAge, this.maxAge});

  factory Eligibility.fromJson(Map<String, Object?> json) {
    final sex = json['sex'];
    final parsed = switch (sex) {
      null || 'any' => null,
      'male' => Sex.male,
      'female' => Sex.female,
      _ => throw FormatException('"eligibility.sex" cannot be "$sex"'),
    };
    return Eligibility(
      sex: parsed,
      minAge: _optional(json, 'minAge'),
      maxAge: _optional(json, 'maxAge'),
    );
  }

  static AgeOffset? _optional(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map) throw FormatException('"eligibility.$key" must be ages');
    return AgeOffset.fromJson(value.cast<String, Object?>());
  }

  /// Null means the rule applies regardless of sex.
  final Sex? sex;

  /// The earliest age an occurrence of this rule can fall due. Anything before
  /// it is not generated at all.
  final AgeOffset? minAge;

  /// The age past which the rule stops being this person's concern, judged
  /// against their age *today* rather than against the window. A childhood
  /// check-up that lapsed decades ago is noise on an adult's timeline, while
  /// the same lapsed check-up still matters to the parent of a three-year-old.
  final AgeOffset? maxAge;
}

/// One entitlement in a catalog: what it is, who it applies to, when it falls
/// due, and where that came from.
class Rule {
  const Rule({
    required this.id,
    required this.catalogId,
    required this.title,
    required this.description,
    required this.schedule,
    required this.source,
    this.eligibility = const Eligibility(),
    this.statutory = true,
    this.optional = false,
    this.retiredOn,
  });

  factory Rule.fromJson(
    Map<String, Object?> json, {
    required String catalogId,
    required Map<String, SourceRef> sources,
  }) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('every rule needs an "id"');
    }
    try {
      final sourceId = json['source'];
      if (sourceId is! String) {
        throw const FormatException('"source" is required');
      }
      final source = sources[sourceId];
      if (source == null) {
        throw FormatException('"source" does not resolve: "$sourceId"');
      }
      final schedule = json['schedule'];
      if (schedule is! Map) {
        throw const FormatException('"schedule" is required');
      }
      final eligibility = json['eligibility'];
      return Rule(
        id: id,
        catalogId: catalogId,
        title: LocalizedText.fromJson(json['title']),
        description: LocalizedText.fromJson(json['description']),
        schedule: Schedule.fromJson(schedule.cast<String, Object?>()),
        source: source,
        eligibility: eligibility == null
            ? const Eligibility()
            : Eligibility.fromJson((eligibility as Map).cast()),
        statutory: json['statutory'] != false,
        optional: json['optional'] == true,
        retiredOn: _retiredOn(json['retiredOn']),
      );
    } on FormatException catch (e) {
      throw FormatException('rule "$id": ${e.message}');
    }
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DateTime? _retiredOn(Object? value) {
    if (value == null) return null;
    if (value is! String || !_isoDate.hasMatch(value)) {
      throw const FormatException('"retiredOn" must be a date, yyyy-mm-dd');
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    if (date == null || date.toIso8601String().substring(0, 10) != value) {
      throw FormatException('"retiredOn" is not a valid date: "$value"');
    }
    return date;
  }

  final String id;
  final String catalogId;
  final LocalizedText title;
  final LocalizedText description;
  final Schedule schedule;
  final SourceRef source;
  final Eligibility eligibility;

  /// False for services that are not a standard statutory benefit and depend on
  /// the insurer, such as U10, U11 and J2. Shown as such in the app so nobody
  /// arrives at a practice expecting it to be covered.
  final bool statutory;

  /// True for vaccinations whose indication the app cannot know, such as a
  /// risk area or a pregnancy. Never generated unless a person has switched
  /// the rule on; see [Person.optionalRules].
  final bool optional;

  /// The date from which the guideline no longer grants this entitlement.
  ///
  /// A rule is retired rather than removed: recorded appointments are keyed
  /// by its id and have to stay readable. From this date on nothing new is
  /// planned; what was recorded still shows as done.
  final DateTime? retiredOn;

  @override
  String toString() => 'Rule($catalogId/$id)';
}
