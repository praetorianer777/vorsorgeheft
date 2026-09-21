import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/age_offset.dart';
import 'package:vorsorgeheft/domain/occurrence.dart';
import 'package:vorsorgeheft/domain/rule.dart';
import 'package:vorsorgeheft/domain/schedule.dart';
import 'package:vorsorgeheft/domain/source_ref.dart';
import 'package:vorsorgeheft/domain/localized_text.dart';
import 'package:vorsorgeheft/l10n/app_localizations.dart';
import 'package:vorsorgeheft/ui/relative_time.dart';
import 'package:vorsorgeheft/ui/timeline_screen.dart';

final _today = DateTime.utc(2026, 9, 20);

final _rule = Rule(
  id: 'r',
  catalogId: 'c',
  title: const LocalizedText({'en': 'R', 'de': 'R'}),
  description: const LocalizedText({'en': 'R', 'de': 'R'}),
  schedule: const OnceFromAge(from: AgeOffset()),
  source: SourceRef(
    id: 's',
    name: const LocalizedText({'en': 'S', 'de': 'S'}),
    url: 'https://example.org',
    asOf: _today,
  ),
);

Occurrence _occ(
  OccurrenceStatus status, {
  required DateTime start,
  DateTime? end,
  DateTime? deadline,
}) => Occurrence(
  personId: 'p',
  rule: _rule,
  windowStart: start,
  windowEnd: end,
  deadline: deadline,
  status: status,
);

void main() {
  late AppLocalizations en;
  late AppLocalizations de;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  test(
    'an entitlement that opened years ago and never closes says nothing',
    () {
      final measles = _occ(
        OccurrenceStatus.due,
        start: DateTime.utc(2006, 6, 30),
      );
      expect(formatTimelineDistance(en, measles, _today), isNull);
    },
  );

  test(
    'a running window says how long is left, not how long ago it opened',
    () {
      final checkup = _occ(
        OccurrenceStatus.due,
        start: DateTime.utc(2026, 6, 30),
        end: DateTime.utc(2029, 6, 30),
      );
      expect(formatTimelineDistance(en, checkup, _today), '3 years left');
      expect(formatTimelineDistance(de, checkup, _today), 'noch 3 Jahre');
    },
  );

  test('an overdue check-up with a deadline counts down to the deadline', () {
    final u3 = _occ(
      OccurrenceStatus.overdue,
      start: DateTime.utc(2026, 8, 1),
      end: DateTime.utc(2026, 9, 1),
      deadline: DateTime.utc(2026, 10, 4),
    );
    expect(formatTimelineDistance(en, u3, _today), '2 weeks left');
  });

  test('an overdue entry without a deadline says when it closed', () {
    final hearing = _occ(
      OccurrenceStatus.overdue,
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 9, 3),
    );
    expect(formatTimelineDistance(en, hearing, _today), '2 weeks ago');
  });

  test('upcoming counts to the window opening', () {
    final u6 = _occ(
      OccurrenceStatus.upcoming,
      start: DateTime.utc(2026, 9, 22),
    );
    expect(formatTimelineDistance(en, u6, _today), 'in 2 days');
  });

  test('overdue sorts before due, and the soonest deadline first', () {
    final dueLater = _occ(
      OccurrenceStatus.due,
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2029, 1, 1),
    );
    final dueOpenEnded = _occ(
      OccurrenceStatus.due,
      start: DateTime.utc(2006, 1, 1),
    );
    final overdueSoon = _occ(
      OccurrenceStatus.overdue,
      start: DateTime.utc(2026, 8, 1),
      end: DateTime.utc(2026, 9, 1),
      deadline: DateTime.utc(2026, 10, 1),
    );
    final overdueNoDeadline = _occ(
      OccurrenceStatus.overdue,
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 9, 1),
    );

    final sorted = [dueOpenEnded, dueLater, overdueNoDeadline, overdueSoon]
      ..sort(compareUrgency);
    expect(sorted, [overdueNoDeadline, overdueSoon, dueLater, dueOpenEnded]);
  });
}
