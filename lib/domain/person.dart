/// Whether sex-specific entitlements apply to a person.
///
/// Recorded only to work out which screenings someone is entitled to; several
/// German screening programmes are defined by sex. [notStated] is the default,
/// and sex-specific rules then surface as possibly applicable rather than as
/// due, so leaving the field empty never hides an entitlement outright.
enum Sex { male, female, notStated }

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.dateOfBirth,
    this.sex = Sex.notStated,
    this.notes,
    this.optionalRules = const {},
  });

  final String id;
  final String name;

  /// Midnight UTC on the day of birth. Times of day only matter for the
  /// newborn screenings, which are measured in hours of life; [birthInstant]
  /// carries that precision when it is known.
  final DateTime dateOfBirth;

  final Sex sex;
  final String? notes;

  /// The ids of the optional rules switched on for this person. Everything
  /// else marked optional in a catalog stays off their timeline.
  final Set<String> optionalRules;

  DateTime get birthInstant => dateOfBirth;

  @override
  String toString() => 'Person($id, $name)';
}
