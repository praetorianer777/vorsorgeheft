import 'package:vorsorgereminder/domain/person.dart';

/// Today, pinned for every integration run.
///
/// Nothing in the suite may read the wall clock: an expectation about which
/// check-up is due would otherwise start failing on its own as the calendar
/// moves, months after the code it covers last changed.
final pinnedToday = DateTime.utc(2026, 9, 20);

/// A family that puts every state of the timeline on screen at once: an infant
/// with appointments already lapsed, a school-age child in the gap the
/// non-statutory examinations fill, and two adults far enough apart in age that
/// their entitlements differ.
class Family {
  static final infant = Person(
    id: 'infant',
    name: 'Mila',
    dateOfBirth: DateTime.utc(2026, 9, 1),
  );

  static final schoolAge = Person(
    id: 'school-age',
    name: 'Jonas',
    dateOfBirth: DateTime.utc(2018, 4, 12),
    sex: Sex.male,
  );

  static final mother = Person(
    id: 'mother',
    name: 'Sara',
    dateOfBirth: DateTime.utc(1988, 6, 30),
    sex: Sex.female,
  );

  static final father = Person(
    id: 'father',
    name: 'Tim',
    dateOfBirth: DateTime.utc(1960, 2, 29),
    sex: Sex.male,
  );

  static final all = [infant, schoolAge, mother, father];
}
