import 'age_offset.dart';
import 'localized_text.dart';
import 'rule.dart';
import 'schedule.dart';
import 'source_ref.dart';

/// An appointment a person added themselves, outside any guideline: the eye
/// check for a short-sighted child, the blood test that comes with a
/// condition, the professional dental cleaning. Repeats from a first date at
/// a fixed interval and is otherwise treated like any catalog rule.
class OwnAppointment {
  const OwnAppointment({
    required this.id,
    required this.personId,
    required this.title,
    required this.firstOn,
    required this.everyMonths,
    this.note,
  }) : assert(everyMonths > 0, 'an own appointment repeats at least monthly');

  /// The prefix that keeps own rule ids apart from catalog rule ids, which
  /// share the completions table with them.
  static const rulePrefix = 'own:';

  /// The catalog id and source id under which own rules appear.
  static const catalogId = 'own';

  final String id;
  final String personId;
  final String title;
  final DateTime firstOn;
  final int everyMonths;
  final String? note;

  String get ruleId => '$rulePrefix$id';

  static bool isOwnRule(String ruleId) => ruleId.startsWith(rulePrefix);

  OwnAppointment copyWith({
    String? title,
    DateTime? firstOn,
    int? everyMonths,
    String? Function()? note,
  }) => OwnAppointment(
    id: id,
    personId: personId,
    title: title ?? this.title,
    firstOn: firstOn ?? this.firstOn,
    everyMonths: everyMonths ?? this.everyMonths,
    note: note == null ? this.note : note(),
  );

  /// The rule the engine schedules. The text is the same in every language,
  /// because it is the person's own words; [sourceName] is the one piece of
  /// UI copy, passed in so the domain stays free of localisation.
  Rule toRule({LocalizedText? sourceName}) {
    final text = LocalizedText({
      for (final locale in LocalizedText.supportedLocales) locale: title,
    });
    final description = LocalizedText({
      for (final locale in LocalizedText.supportedLocales)
        locale: note?.trim().isNotEmpty ?? false ? note!.trim() : title,
    });
    return Rule(
      id: ruleId,
      catalogId: catalogId,
      title: text,
      description: description,
      schedule: RecurringFromDate(
        first: firstOn,
        every: AgeOffset(months: everyMonths),
      ),
      source: SourceRef(
        id: catalogId,
        name: sourceName ?? text,
        url: '',
        asOf: firstOn,
      ),
      own: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OwnAppointment &&
      other.id == id &&
      other.personId == personId &&
      other.title == title &&
      other.firstOn == firstOn &&
      other.everyMonths == everyMonths &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(id, personId, title, firstOn, everyMonths, note);

  @override
  String toString() => 'OwnAppointment($id: $title every $everyMonths months)';
}
