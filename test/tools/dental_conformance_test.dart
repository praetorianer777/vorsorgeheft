import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/age_offset.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// Reads §§ 4 and 9 of the FU-Richtlinie and holds the catalog to them, the
/// way [children_conformance_test.dart] does for the Kinder-Richtlinie.
///
/// The two guidelines count differently, and that is the point of reading
/// this one separately: the Kinder-RL names a period ("10.-12. Lebensmonat",
/// which ends before the twelfth month is complete), the FU-RL names its end
/// by completion ("vom 6. bis zum vollendeten 9. Lebensmonat", which ends the
/// day the ninth month is complete). A window copied from one style into the
/// other is off by a month, and nothing but this would say so.
void main() {
  final document = File(
    'tools/catalog-sources/gba-zahn-frueherkennung.txt',
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final catalog = catalogNamed('dental');
  final birth = DateTime.utc(2021, 3, 8);

  /// `vom 6. bis zum vollendeten 9. (Z1)`, with the unit named once at the
  /// end of the sentence.
  final windows = <String, ({int from, int to})>{};
  for (final match in RegExp(
    r'vom (\d+)\. bis zum vollendeten (\d+)\.(?: Lebensmonat)? \((Z\d)\)',
  ).allMatches(document)) {
    windows[match.group(3)!.toLowerCase()] = (
      from: int.parse(match.group(1)!),
      to: int.parse(match.group(2)!),
    );
  }

  test('the guideline still names six examinations with their months', () {
    expect(windows.keys.toList()..sort(), [
      'z1',
      'z2',
      'z3',
      'z4',
      'z5',
      'z6',
    ], reason: '§§ 4 and 9 no longer read as they did');
  });

  test('the catalog carries exactly those six', () {
    final inCatalog = catalog.rules
        .map((r) => r.id)
        .where((id) => RegExp(r'^z\d$').hasMatch(id))
        .toSet();
    expect(inCatalog, windows.keys.toSet());
  });

  test('no gap and no overlap between one window and the next', () {
    // The guideline hands out three examinations per period and leaves no
    // month unaccounted for; a catalog that did would drop an entitlement.
    final ordered = windows.keys.toList()..sort();
    for (var i = 1; i < ordered.length; i++) {
      expect(
        windows[ordered[i]]!.from,
        windows[ordered[i - 1]]!.to + 1,
        reason: '${ordered[i - 1]} to ${ordered[i]}',
      );
    }
  });

  group('every window matches the guideline', () {
    for (final id in ['z1', 'z2', 'z3', 'z4', 'z5', 'z6']) {
      test(id, () {
        final months = windows[id]!;
        final schedule = catalog.rules.singleWhere((r) => r.id == id).schedule;
        expect(schedule, isA<AgeWindow>(), reason: id);
        final window = schedule as AgeWindow;

        // The nth month of life begins n-1 months after birth.
        expect(
          window.from.applyTo(birth),
          AgeOffset(months: months.from - 1).applyTo(birth),
          reason: '$id opens with the ${months.from}. Lebensmonat',
        );
        // "bis zum vollendeten n." ends the day that month is complete.
        expect(
          window.to.applyTo(birth),
          AgeOffset(months: months.to).applyTo(birth),
          reason: '$id runs to the completed ${months.to}. Lebensmonat',
        );
        // There is no catching up: the FU-RL names no tolerance, so the
        // window is its own limit.
        expect(window.toleranceTo, window.to, reason: id);
        expect(window.hardDeadline, isTrue, reason: id);
      });
    }
  });

  test('the minimum interval the app does not model is still four months', () {
    // Nothing schedules around the four months the guideline wants between
    // two examinations; the windows are far enough apart that keeping to
    // them keeps the interval anyway. Were the guideline to shorten the
    // windows or lengthen the interval, that would stop being true.
    expect(
      document,
      contains(
        'Der Abstand zwischen zwei Früherkennungsuntersuchungen '
        'beträgt mindestens vier Monate',
      ),
    );
    for (final pair in [('z1', 'z2'), ('z2', 'z3')]) {
      expect(
        windows[pair.$2]!.from - windows[pair.$1]!.to,
        greaterThanOrEqualTo(0),
        reason: '${pair.$1} and ${pair.$2} overlap',
      );
    }
  });
}
