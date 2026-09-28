import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/rule.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// Holds the adult check-ups to § 2 of each part of the GU-Richtlinie.
///
/// The guideline states its entitlements in three sentences rather than in a
/// table, but it states them in numbers: an age, a frequency, a sex. Those
/// are exactly the three things the catalog encodes, so they can be read out
/// and compared rather than trusted.
void main() {
  final document = File(
    'tools/catalog-sources/gba-gesundheitsuntersuchung.txt',
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final catalog = catalogNamed('adults');

  Rule ruleNamed(String id) => catalog.rules.singleWhere((r) => r.id == id);

  /// German spells out small numbers, and the guideline's frequencies are
  /// small.
  const spelled = {'zwei': 2, 'drei': 3, 'vier': 4, 'fünf': 5};

  test('the one check-up before 35 runs from the 18th birthday', () {
    final match = RegExp(
      r'ab Vollendung des (\d+)\. Lebensjahres bis zum Ende des (\d+)\. '
      r'Lebensjahres einmalig Anspruch auf eine allgemeine '
      r'Gesundheitsuntersuchung',
    ).firstMatch(document);
    expect(match, isNotNull, reason: '§ 2 no longer reads as it did');

    final schedule = ruleNamed('checkup-young').schedule as AgeWindow;
    expect(schedule.from.years, int.parse(match!.group(1)!));
    expect(schedule.to.years, int.parse(match.group(2)!));
    expect(
      ruleNamed('checkup-young').eligibility.maxAge?.years,
      int.parse(match.group(2)!),
      reason: 'the entitlement ends where the window does',
    );
  });

  test('from 35 it comes round every three years', () {
    final match = RegExp(
      r'ab Vollendung des (\d+)\. Lebensjahres alle (\w+) Jahre Anspruch auf '
      r'eine allgemeine Gesundheitsuntersuchung',
    ).firstMatch(document);
    expect(match, isNotNull, reason: '§ 2 no longer reads as it did');

    final schedule = ruleNamed('checkup').schedule as Recurring;
    expect(schedule.from.years, int.parse(match!.group(1)!));
    expect(schedule.every.years, spelled[match.group(2)!]);
    expect(schedule.until, isNull, reason: 'the guideline names no upper age');
  });

  test('the hepatitis screening is once, from 35', () {
    final match = RegExp(
      r'Versicherte, die das (\d+)\. Lebensjahr vollendet haben, haben .{0,80}'
      r'einmalig Anspruch auf ein Screening auf Hepatitis-B',
    ).firstMatch(document);
    expect(match, isNotNull, reason: '§ 2 no longer reads as it did');

    final rule = ruleNamed('hepatitis-screening');
    expect((rule.schedule as OnceFromAge).from.years, 35);
    expect(int.parse(match!.group(1)!), 35);
    expect(
      rule.eligibility.sex,
      isNull,
      reason: 'the guideline names no sex for it',
    );
  });

  test('the aneurysm screening is once, for men from 65', () {
    final match = RegExp(
      r'Männliche Versicherte ab Vollendung des (\d+)\. Lebensjahres haben '
      r'einmalig Anspruch auf Teilnahme am Screening auf '
      r'Bauchaortenaneurysmen',
    ).firstMatch(document);
    expect(match, isNotNull, reason: '§ 2 no longer reads as it did');

    final rule = ruleNamed('aortic-aneurysm');
    expect(
      (rule.schedule as OnceFromAge).from.years,
      int.parse(match!.group(1)!),
    );
    expect(rule.eligibility.sex, Sex.male);
  });

  test('nothing else in the catalog claims the GU-Richtlinie', () {
    // Everything the guideline covers is named above; a rule added under
    // this source without being read against § 2 would slip past the four
    // tests otherwise.
    expect(
      catalog.rules
          .where((r) => r.source.id == 'gba-gu-rl')
          .map((r) => r.id)
          .toSet(),
      {'checkup-young', 'checkup', 'hepatitis-screening', 'aortic-aneurysm'},
    );
  });
}
