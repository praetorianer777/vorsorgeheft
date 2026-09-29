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

  group(
    'individual prophylaxis and the adult check-up',
    _individualProphylaxis,
  );

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

/// The prophylaxis and the adult check-up come from three documents, and
/// the one that names the interval is not the one the catalog used to cite.
///
/// The IP-Richtlinie says who is entitled and what the appointment consists
/// of, but for six- to eleven-year-olds it names no interval at all. The
/// catalog claimed once a year, which is half of what the BEMA allows, and
/// nothing noticed because no test read the source.
void _individualProphylaxis() {
  /// Both guidelines are read out of a PDF, which breaks a word across two
  /// lines with a hyphen. Joining those back up is what lets the sentences
  /// below be quoted as a person reads them.
  String flowing(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'-[ \t]*\r?\n\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  final ipRl = flowing('tools/catalog-sources/gba-ip-rl.txt');
  final bema = flowing('tools/catalog-sources/bema.txt');
  final sgb55 = flowing('tools/catalog-sources/sgb5-55.txt');
  final catalog = catalogNamed('dental');

  Recurring scheduleOf(String id) =>
      catalog.rules.singleWhere((r) => r.id == id).schedule as Recurring;

  test('prophylaxis is for six- to seventeen-year-olds', () {
    expect(
      ipRl,
      contains(
        'bei Versicherten fest, die das sechste, aber noch nicht das 18. '
        'Lebensjahr vollendet haben',
      ),
      reason: 'IP-RL A.1 no longer reads as it did',
    );
    expect(
      bema,
      contains(
        'Leistungen nach den Nrn. IP 1 bis IP 5 können nur für Versicherte '
        'abgerechnet werden, die das sechste, aber noch nicht das 18. '
        'Lebensjahr vollendet haben',
      ),
      reason: 'the BEMA age limit changed',
    );

    expect(scheduleOf('ip-6-11').from.years, 6);
    expect(scheduleOf('ip-12-17').until!.years, 18);
  });

  test('it comes once per calendar half-year, at every age', () {
    // The interval is the BEMA's, not the guideline's: this is the sentence
    // the catalog was wrong about.
    expect(
      bema,
      contains(
        'Eine Leistung nach Nr. IP 1 kann je Kalenderhalbjahr einmal '
        'abgerechnet werden',
      ),
      reason: 'the IP 1 interval changed',
    );
    for (final id in ['ip-6-11', 'ip-12-17']) {
      expect(scheduleOf(id).every.months, 6, reason: id);
      expect(scheduleOf(id).every.years, 0, reason: id);
    }
  });

  test('the two halves tile the years between without gap or overlap', () {
    final younger = scheduleOf('ip-6-11');
    final older = scheduleOf('ip-12-17');
    final birth = DateTime.utc(2015, 3, 10);
    expect(
      younger.every.applyTo(younger.until!.applyTo(birth)),
      older.from.applyTo(birth),
      reason: 'the last appointment before twelve is half a year before it',
    );
  });

  test('only from twelve does an appointment count for the bonus', () {
    expect(
      ipRl,
      contains(
        'In ein Bonusheft ist bei den 12- bis 17-Jährigen für jedes '
        'Kalenderhalbjahr das Datum der Erhebung des Mundhygienestatus '
        'einzutragen',
      ),
      reason: 'IP-RL Nr. 13 no longer reads as it did',
    );
    // Which is why the catalog keeps two rules for one entitlement: the
    // appointment is the same, what it is worth is not.
    final bonus = catalog.rules.singleWhere((r) => r.id == 'ip-12-17');
    expect(bonus.description('de'), contains('Bonusheft'));
    expect(
      catalog.rules.singleWhere((r) => r.id == 'ip-6-11').description('de'),
      isNot(contains('Bonusheft')),
    );
  });

  test('the adult check-up is yearly, and starts where the bonus does', () {
    expect(
      sgb55,
      contains(
        'sich nach Vollendung des 18. Lebensjahres nicht wenigstens einmal '
        'in jedem Kalenderjahr hat zahnärztlich untersuchen lassen',
      ),
      reason: '§ 55 Satz 4 Nr. 2 no longer reads as it did',
    );
    final adult = scheduleOf('dental-checkup-adult');
    expect(adult.from.years, 18);
    expect(adult.every.years, 1);
    expect(adult.until, isNull);
  });
}
