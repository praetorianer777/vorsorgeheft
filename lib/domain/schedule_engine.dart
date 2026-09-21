import 'age_offset.dart';
import 'catalog.dart';
import 'completion.dart';
import 'occurrence.dart';
import 'person.dart';
import 'rule.dart';
import 'schedule.dart';

/// Turns a person, the catalogs and what has already been done into that
/// person's list of appointments.
///
/// [today] is passed in rather than read from the clock: nothing in this
/// library calls `DateTime.now()`, so a test pins the date and stays correct as
/// the calendar moves.
///
/// [horizon] caps how far ahead repeating entitlements are generated; without
/// it a check-up every three years would produce occurrences forever. The next
/// one is always generated even when it lies beyond the horizon, so a
/// twenty-year-old still sees that the check-up starts at 35.
List<Occurrence> computeOccurrences({
  required Person person,
  required CatalogSet catalogs,
  required List<Completion> completions,
  required DateTime today,
  Duration horizon = const Duration(days: 730),
}) {
  final history = _History(person.id, completions);
  final generateUntil = today.add(horizon);
  final occurrences = <Occurrence>[];

  for (final rule in catalogs.rules) {
    if (!isSwitchedOn(rule, person: person, catalogs: catalogs)) continue;
    final applicability = _applicability(rule, person);
    if (applicability == null) continue;
    occurrences.addAll(
      _forRule(
        rule: rule,
        person: person,
        history: history,
        today: today,
        generateUntil: generateUntil,
        applicability: applicability,
      ),
    );
  }

  occurrences.sort((a, b) => a.windowStart.compareTo(b.windowStart));
  return List.unmodifiable(occurrences);
}

/// Whether [rule] is on [person]'s timeline at all.
///
/// A standard rule always is. An optional one is only when the person has
/// switched it on, and a booster follows the switch of the series it
/// refreshes: nobody wants a booster reminder for a series they never had,
/// and nobody who had the series wants to switch its booster on separately.
bool isSwitchedOn(
  Rule rule, {
  required Person person,
  required CatalogSet catalogs,
}) {
  if (!rule.optional) return true;
  if (person.optionalRules.contains(rule.id)) return true;
  final schedule = rule.schedule;
  if (schedule is! Booster || schedule.after == null) return false;
  final primary = catalogs.ruleById(schedule.after!);
  return primary != null &&
      primary.id != rule.id &&
      isSwitchedOn(primary, person: person, catalogs: catalogs);
}

/// The optional rules a person can switch on, one switch each. A booster that
/// follows an optional series is not listed, because it takes that series'
/// switch.
List<Rule> switchableRules(CatalogSet catalogs) => [
  for (final rule in catalogs.rules)
    if (rule.optional && !_followsOptionalSeries(rule, catalogs)) rule,
];

bool _followsOptionalSeries(Rule rule, CatalogSet catalogs) {
  final schedule = rule.schedule;
  if (schedule is! Booster || schedule.after == null) return false;
  return catalogs.ruleById(schedule.after!)?.optional ?? false;
}

/// The completions for one person, indexed the way the engine looks them up.
class _History {
  _History(String personId, List<Completion> completions) {
    for (final completion in completions) {
      if (completion.personId != personId) continue;
      _byKey.putIfAbsent(completion.occurrenceKey, () => []).add(completion);
    }
    for (final list in _byKey.values) {
      list.sort((a, b) => a.completedOn.compareTo(b.completedOn));
    }
  }

  final Map<String, List<Completion>> _byKey = {};

  List<Completion> forKey(String ruleId, [String? doseId]) =>
      _byKey[doseId == null ? ruleId : '$ruleId#$doseId'] ?? const [];

  Completion? latest(String ruleId, [String? doseId]) {
    final list = forKey(ruleId, doseId);
    return list.isEmpty ? null : list.last;
  }

  /// The last time this rule was actually carried out, ignoring deliberate
  /// skips: a skipped booster does not restart the interval. For a series
  /// that is the latest dose given, whichever dose it was.
  DateTime? lastDone(String ruleId) {
    for (final completion in forKey(ruleId).reversed) {
      if (!completion.skipped) return completion.completedOn;
    }
    DateTime? latest;
    for (final entry in _byKey.entries) {
      if (!entry.key.startsWith('$ruleId#')) continue;
      for (final completion in entry.value.reversed) {
        if (completion.skipped) continue;
        if (latest == null || completion.completedOn.isAfter(latest)) {
          latest = completion.completedOn;
        }
        break;
      }
    }
    return latest;
  }
}

/// Null when the rule cannot apply to this person at all.
Applicability? _applicability(Rule rule, Person person) {
  final required = rule.eligibility.sex;
  if (required == null) return Applicability.definite;
  if (person.sex == required) return Applicability.definite;
  if (person.sex == Sex.notStated) return Applicability.possible;
  return null;
}

Iterable<Occurrence> _forRule({
  required Rule rule,
  required Person person,
  required _History history,
  required DateTime today,
  required DateTime generateUntil,
  required Applicability applicability,
}) {
  final birth = person.dateOfBirth;

  final maxAge = rule.eligibility.maxAge?.applyTo(birth);
  if (maxAge != null && today.isAfter(maxAge)) return const [];

  Occurrence make({
    required DateTime windowStart,
    DateTime? windowEnd,
    DateTime? deadline,
    String? instanceId,
    Completion? completion,
    bool provisional = false,
  }) => Occurrence(
    personId: person.id,
    rule: rule,
    instanceId: instanceId,
    windowStart: windowStart,
    windowEnd: windowEnd,
    deadline: deadline,
    status: _status(
      today: today,
      windowStart: windowStart,
      windowEnd: windowEnd,
      deadline: deadline,
      completion: completion,
    ),
    completedOn: completion?.completedOn,
    applicability: applicability,
    provisional: provisional,
  );

  final generated = switch (rule.schedule) {
    AgeWindow(
      :final from,
      :final to,
      :final toleranceTo,
      :final hardDeadline,
    ) =>
      [
        make(
          windowStart: from.applyTo(birth),
          windowEnd: to.applyTo(birth),
          deadline: hardDeadline ? toleranceTo!.applyTo(birth) : null,
          completion: history.latest(rule.id),
        ),
      ],

    OnceFromAge(:final from, :final until) => [
      make(
        windowStart: from.applyTo(birth),
        windowEnd: until?.applyTo(birth),
        completion: history.latest(rule.id),
      ),
    ],

    Recurring(:final from, :final every, :final until) => _recurring(
      rule: rule,
      birth: birth,
      from: from,
      every: every,
      untilAge: until,
      history: history,
      today: today,
      generateUntil: generateUntil,
      make: make,
    ),

    Series(:final doses) => _series(
      rule: rule,
      birth: birth,
      doses: doses,
      history: history,
      make: make,
    ),

    Booster(:final every, :final after, :final fromAge, :final thenEvery) =>
      _booster(
        rule: rule,
        birth: birth,
        every: every,
        thenEvery: thenEvery ?? every,
        afterRuleId: after ?? rule.id,
        fromAge: fromAge,
        history: history,
        today: today,
        generateUntil: generateUntil,
        make: make,
      ),
  };

  final minAge = rule.eligibility.minAge?.applyTo(birth);
  final retiredOn = rule.retiredOn;
  return generated.where(
    (o) =>
        (minAge == null || !o.windowStart.isBefore(minAge)) &&
        (retiredOn == null ||
            o.completedOn != null ||
            o.windowStart.isBefore(retiredOn)),
  );
}

typedef _Make =
    Occurrence Function({
      required DateTime windowStart,
      DateTime? windowEnd,
      DateTime? deadline,
      String? instanceId,
      Completion? completion,
      bool provisional,
    });

/// Each past completion becomes one settled occurrence, and the interval to the
/// next one counts from the most recent of them - somebody who had the check-up
/// a year early is next due three years after that, not on the original grid.
List<Occurrence> _recurring({
  required Rule rule,
  required DateTime birth,
  required AgeOffset from,
  required AgeOffset every,
  required AgeOffset? untilAge,
  required _History history,
  required DateTime today,
  required DateTime generateUntil,
  required _Make make,
}) {
  final occurrences = <Occurrence>[];
  final past = history.forKey(rule.id);

  for (final completion in past) {
    occurrences.add(
      make(
        windowStart: completion.completedOn,
        windowEnd: completion.completedOn,
        instanceId: _instanceId(completion.completedOn),
        completion: completion,
      ),
    );
  }

  final anchor = history.lastDone(rule.id);
  var due = anchor == null ? from.applyTo(birth) : every.applyTo(anchor);
  final cutoff = untilAge?.applyTo(birth);
  due = _currentRepeat(due, every, today, cutoff);

  // With an age limit the last repeat can have elapsed entirely. Nothing can
  // be caught up after that, so the rule is over rather than overdue, and only
  // what was actually recorded stays on the timeline.
  if (cutoff != null && every.applyTo(due).isBefore(today)) return occurrences;

  var emitted = 0;
  while (cutoff == null || !due.isAfter(cutoff)) {
    if (emitted > 0 && due.isAfter(generateUntil)) break;
    occurrences.add(
      make(
        windowStart: due,
        windowEnd: every.applyTo(due),
        instanceId: _instanceId(due),
      ),
    );
    emitted++;
    due = every.applyTo(due);
  }

  return occurrences;
}

/// A dose is due no earlier than its own age window and no earlier than the
/// minimum gap after the dose before it was actually given. While that previous
/// dose is unrecorded the gap cannot be applied, so the window is derived from
/// age alone and the occurrence is marked provisional.
List<Occurrence> _series({
  required Rule rule,
  required DateTime birth,
  required List<Dose> doses,
  required _History history,
  required _Make make,
}) {
  final occurrences = <Occurrence>[];
  DateTime? previousDoseGivenOn;
  var previousRecorded = true;

  for (final dose in doses) {
    final completion = history.latest(rule.id, dose.id);
    var windowStart = dose.from.applyTo(birth);
    var provisional = false;

    final gap = dose.minIntervalFromPrevious;
    if (gap != null) {
      if (previousDoseGivenOn != null) {
        final earliest = gap.applyTo(previousDoseGivenOn);
        if (earliest.isAfter(windowStart)) windowStart = earliest;
      } else if (!previousRecorded) {
        provisional = true;
      }
    }

    occurrences.add(
      make(
        windowStart: windowStart,
        windowEnd: dose.to?.applyTo(birth),
        instanceId: dose.id,
        completion: completion,
        provisional: provisional,
      ),
    );

    previousRecorded = completion != null && !completion.skipped;
    previousDoseGivenOn = previousRecorded ? completion.completedOn : null;
  }

  return occurrences;
}

/// A booster counts from the last dose actually given, of this rule or of the
/// primary series it refreshes, whichever is later. With nothing recorded it
/// falls back to an age, and with neither it produces nothing rather than
/// guessing.
///
/// [every] is the interval after the primary series or the age fallback;
/// [thenEvery] the one after a booster, and between the repeats generated
/// ahead, since each of those assumes the one before it was given.
List<Occurrence> _booster({
  required Rule rule,
  required DateTime birth,
  required AgeOffset every,
  required AgeOffset thenEvery,
  required String afterRuleId,
  required AgeOffset? fromAge,
  required _History history,
  required DateTime today,
  required DateTime generateUntil,
  required _Make make,
}) {
  // Ten years from the last tetanus shot means the last one actually given:
  // once a booster has been had, it is the anchor, not the childhood series it
  // originally refreshed.
  final own = history.lastDone(rule.id);
  final previous = history.lastDone(afterRuleId);
  final anchor = own == null || (previous != null && previous.isAfter(own))
      ? previous
      : own;
  if (anchor == null && fromAge == null) return const [];

  final occurrences = <Occurrence>[];
  for (final completion in history.forKey(rule.id)) {
    occurrences.add(
      make(
        windowStart: completion.completedOn,
        windowEnd: completion.completedOn,
        instanceId: _instanceId(completion.completedOn),
        completion: completion,
      ),
    );
  }

  final first = anchor == null
      ? fromAge!.applyTo(birth)
      : (own == null ? every : thenEvery).applyTo(anchor);
  var due = _currentRepeat(first, thenEvery, today, null);
  var emitted = 0;
  while (emitted == 0 || !due.isAfter(generateUntil)) {
    occurrences.add(make(windowStart: due, instanceId: _instanceId(due)));
    emitted++;
    due = thenEvery.applyTo(due);
  }

  return occurrences;
}

/// The repeat that can still be acted on, skipping the ones a later repeat has
/// already superseded.
///
/// An entitlement that comes round every year has one instance that matters:
/// the one running now. Emitting every missed repeat since somebody turned
/// eighteen buries it under twenty years of appointments nobody can make any
/// more, and turns the whole timeline into noise.
DateTime _currentRepeat(
  DateTime first,
  AgeOffset every,
  DateTime today,
  DateTime? cutoff,
) {
  var due = first;
  while (true) {
    final next = every.applyTo(due);
    if (next.isAfter(today)) return due;
    if (cutoff != null && next.isAfter(cutoff)) return due;
    due = next;
  }
}

String _instanceId(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

OccurrenceStatus _status({
  required DateTime today,
  required DateTime windowStart,
  required DateTime? windowEnd,
  required DateTime? deadline,
  required Completion? completion,
}) {
  if (completion != null) {
    return completion.skipped
        ? OccurrenceStatus.skipped
        : OccurrenceStatus.done;
  }
  if (deadline != null && today.isAfter(deadline)) {
    return OccurrenceStatus.expired;
  }
  if (today.isBefore(windowStart)) return OccurrenceStatus.upcoming;
  if (windowEnd == null || !today.isAfter(windowEnd)) {
    return OccurrenceStatus.due;
  }
  return OccurrenceStatus.overdue;
}
