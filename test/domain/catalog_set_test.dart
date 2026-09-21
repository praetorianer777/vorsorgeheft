import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/domain/age_offset.dart';
import 'package:vorsorgereminder/domain/localized_text.dart';
import 'package:vorsorgereminder/domain/schedule.dart';

import '../support/catalogs.dart';

/// What every shipped catalog has to satisfy, whatever it is about. The
/// sourcing promise the app makes is only worth something if it is enforced
/// here rather than checked by hand.
void main() {
  final set = shippedCatalogs();

  test('all four catalogs ship', () {
    expect(set.catalogs.map((c) => c.id), [
      'children',
      'vaccinations',
      'dental',
      'adults',
    ]);
  });

  test('every rule names a resolvable source with an as-of date', () {
    for (final rule in set.rules) {
      expect(rule.source.url, startsWith('https://'), reason: rule.id);
      expect(
        rule.source.asOf.year,
        greaterThanOrEqualTo(2020),
        reason: rule.id,
      );
    }
  });

  test('every rule and every source reads in both languages', () {
    for (final rule in set.rules) {
      for (final locale in LocalizedText.supportedLocales) {
        expect(rule.title(locale), isNotEmpty, reason: '${rule.id}/$locale');
        expect(
          rule.description(locale),
          isNotEmpty,
          reason: '${rule.id}/$locale',
        );
        expect(
          rule.source.name(locale),
          isNotEmpty,
          reason: '${rule.source.id}/$locale',
        );
      }
    }
  });

  test('rule ids are unique across catalogs', () {
    // They have to be: an occurrence key is person plus rule id, so two rules
    // sharing an id would share a completion and a notification.
    final ids = set.rules.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the German text is really German', () {
    for (final rule in set.rules) {
      expect(
        rule.description('de'),
        isNot(equals(rule.description('en'))),
        reason: rule.id,
      );
    }
  });

  group('schedules are internally consistent', () {
    // Offsets mix units, so they are compared by what they do to one date
    // rather than field by field.
    final birth = DateTime.utc(2000, 1, 1);
    DateTime at(AgeOffset offset) => offset.applyTo(birth);

    test('every booster refers to a rule that exists', () {
      for (final rule in set.rules) {
        final schedule = rule.schedule;
        if (schedule is! Booster || schedule.after == null) continue;
        expect(set.ruleById(schedule.after!), isNotNull, reason: rule.id);
      }
    });

    test('every window opens before it closes', () {
      for (final rule in set.rules) {
        final schedule = rule.schedule;
        switch (schedule) {
          case AgeWindow(:final from, :final to):
            expect(at(from).isBefore(at(to)), isTrue, reason: rule.id);
          case Recurring(:final from, :final until?):
            expect(at(from).isBefore(at(until)), isTrue, reason: rule.id);
          case OnceFromAge(:final from, :final until?):
            expect(at(from).isBefore(at(until)), isTrue, reason: rule.id);
          case Series(:final doses):
            for (final dose in doses) {
              final to = dose.to;
              if (to == null) continue;
              expect(
                at(dose.from).isBefore(at(to)),
                isTrue,
                reason: '${rule.id}/${dose.id}',
              );
            }
          case _:
            break;
        }
      }
    });

    test('a tolerance limit never falls before the window it extends', () {
      for (final rule in set.rules) {
        final schedule = rule.schedule;
        if (schedule is! AgeWindow || schedule.toleranceTo == null) continue;
        expect(
          at(schedule.toleranceTo!).isBefore(at(schedule.to)),
          isFalse,
          reason: rule.id,
        );
      }
    });

    test('no interval is zero, which would repeat forever', () {
      for (final rule in set.rules) {
        final every = switch (rule.schedule) {
          Recurring(:final every) => every,
          Booster(:final every) => every,
          _ => null,
        };
        if (every == null) continue;
        expect(at(every).isAfter(birth), isTrue, reason: rule.id);
      }
    });

    test('the doses of a series are in age order', () {
      for (final rule in set.rules) {
        final schedule = rule.schedule;
        if (schedule is! Series) continue;
        final starts = schedule.doses.map((d) => at(d.from)).toList();
        for (var i = 1; i < starts.length; i++) {
          expect(
            starts[i].isBefore(starts[i - 1]),
            isFalse,
            reason: '${rule.id}/${schedule.doses[i].id}',
          );
        }
      }
    });

    test('an age floor sits below the age ceiling', () {
      for (final rule in set.rules) {
        final min = rule.eligibility.minAge;
        final max = rule.eligibility.maxAge;
        if (min == null || max == null) continue;
        expect(at(min).isBefore(at(max)), isTrue, reason: rule.id);
      }
    });
  });

  test('no source claims to have been reviewed in the future', () {
    for (final source in set.sources) {
      expect(
        source.asOf.isAfter(DateTime.now().toUtc()),
        isFalse,
        reason: source.id,
      );
    }
  });
}
