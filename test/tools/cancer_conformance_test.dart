import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/domain/rule.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// Holds the cancer screenings to the two guidelines they come from.
///
/// Both documents are long, and both end in leaflets for insured people that
/// repeat every number in prose, once for men and once for women: "Frauen ab
/// 50 Jahren alle zwei Jahre" appears in the entitlement and again in a
/// brochure three hundred lines further down. A pattern matched against the
/// whole document would find the brochure. Everything below is therefore read
/// out of one named section, and a section that stops parsing fails rather
/// than quietly matching somewhere else.
void main() {
  final kfe = _Guideline('tools/catalog-sources/gba-krebsfrueherkennung.txt');
  final okfe = _Guideline('tools/catalog-sources/gba-okfe-rl.txt');
  final catalog = catalogNamed('adults');

  Rule ruleNamed(String id) => catalog.rules.singleWhere((r) => r.id == id);

  Set<String> rulesFrom(String sourceId) => catalog.rules
      .where((r) => r.source.id == sourceId)
      .map((r) => r.id)
      .toSet();

  group('the Krebsfrüherkennungs-Richtlinie', () {
    /// § 1 (2) lists every age the guideline grants something at, in one
    /// place and in one sentence each. It is the closest this document comes
    /// to the table the Kinder-Richtlinie has.
    late final overview = kfe.section('1');

    test('the overview of ages still parses', () {
      expect(overview, contains('bei Frauen'));
      expect(overview, contains('bei Männern'));
      expect(overview, contains('bei Frauen und Männern'));
    });

    test('the clinical examination for women runs yearly from 20', () {
      expect(
        overview,
        contains(
          'der Früherkennung von Krebserkrankungen des Genitales ab dem '
          'Alter von 20 Jahren',
        ),
      );
      // § 2: everything in this guideline is yearly unless its own section
      // says otherwise, and the clinical examination has no such section.
      expect(
        kfe.section('2'),
        contains(
          'Der Anspruch auf Früherkennung besteht nach der ersten '
          'Inanspruchnahme',
        ),
      );
      expect(kfe.section('2'), contains('jährlich'));

      final schedule = ruleNamed('gynaecological-exam').schedule as Recurring;
      expect(schedule.from.years, 20);
      expect(schedule.every.years, 1);
      expect(ruleNamed('gynaecological-exam').eligibility.sex, Sex.female);
    });

    test('the clinical examination for men runs yearly from 45', () {
      expect(
        overview,
        contains(
          'der Früherkennung von Krebserkrankungen der Prostata und des '
          'äußeren Genitales ab dem Alter von 45 Jahren',
        ),
      );

      final schedule = ruleNamed('prostate-exam').schedule as Recurring;
      expect(schedule.from.years, 45);
      expect(schedule.every.years, 1);
      expect(ruleNamed('prostate-exam').eligibility.sex, Sex.male);
    });

    test('mammography runs every 24 months from 50 to 75', () {
      final match = RegExp(
        r'Frauen haben grundsätzlich alle (\d+) Monate, erstmalig ab dem '
        r'Alter von (\d+) Jahren.{0,140}?höchstens bis zum Alter von (\d+) '
        r'Jahren',
      ).firstMatch(kfe.section('10'));
      expect(match, isNotNull, reason: '§ 10 no longer reads as it did');

      final rule = ruleNamed('mammography');
      final schedule = rule.schedule as Recurring;
      expect(schedule.every.years * 12, int.parse(match!.group(1)!));
      expect(schedule.from.years, int.parse(match.group(2)!));
      expect(schedule.until!.years, int.parse(match.group(3)!));
      // "up to the age of 75" is the last year it may be had in, so the
      // entitlement ends on the 76th birthday.
      expect(
        rule.eligibility.maxAge!.years,
        int.parse(match.group(3)!) + 1,
        reason: 'the entitlement ends a year after the last age named',
      );
      expect(rule.eligibility.sex, Sex.female);
    });

    test('the skin cancer screening runs every second year from 35', () {
      final match = RegExp(
        r'Versicherte haben ab dem Alter von (\d+) Jahren jedes (zweite) '
        r'Jahr Anspruch',
      ).firstMatch(kfe.section('29'));
      expect(match, isNotNull, reason: '§ 29 no longer reads as it did');

      final schedule = ruleNamed('skin-cancer').schedule as Recurring;
      expect(schedule.from.years, int.parse(match!.group(1)!));
      expect(schedule.every.years, 2);
      expect(
        ruleNamed('skin-cancer').eligibility.sex,
        isNull,
        reason: 'the guideline grants it to everyone',
      );
    });

    test('the lung cancer screening is still only for a smoking history', () {
      // The catalog leaves it out on purpose, which only holds while the
      // entitlement depends on something the app never asks about. Were § 38
      // to drop the cigarette condition, the screening would become an
      // ordinary age-based entitlement and its absence a gap.
      final section = kfe.section('38');
      expect(
        section,
        contains(
          'Versicherte Personen, die das 50., aber noch nicht das 76. '
          'Lebensjahr vollendet haben, mit einem Zigarettenkonsum',
        ),
        reason: '§ 38 no longer ties the entitlement to smoking',
      );
      expect(catalog.rules.map((r) => r.id), isNot(contains('lung-cancer')));
    });

    test('nothing else in the catalog claims this guideline', () {
      expect(rulesFrom('gba-kfe-rl'), {
        'skin-cancer',
        'gynaecological-exam',
        'mammography',
        'prostate-exam',
      });
    });
  });

  group('the organised programmes', () {
    /// Part II § 3 for bowel cancer, part III § 3 for cervical cancer. The
    /// general part has a § 3 of its own that only says the programmes each
    /// set their own conditions, so the section is picked by what it
    /// contains rather than by its number alone.
    late final bowel = okfe.section('3', containing: 'occultes Blut im Stuhl');
    late final cervix = okfe.section('3', containing: 'Zervixkarzinom');

    test('the stool test runs every two years from 50', () {
      final match = RegExp(
        r'Versicherte Personen ab dem Alter von (\d+) Jahren können zwischen '
        r'einem Test auf occultes Blut im Stuhl, der alle (\w+) Jahre '
        r'durchgeführt wird',
      ).firstMatch(bowel);
      expect(match, isNotNull, reason: 'part II § 3 no longer reads as it did');

      final schedule = ruleNamed('colorectal-stool-test').schedule as Recurring;
      expect(schedule.from.years, int.parse(match!.group(1)!));
      expect(match.group(2), 'zwei');
      expect(schedule.every.years, 2);
    });

    test('there are two colonoscopies, ten years apart', () {
      expect(
        bowel,
        contains('Es sind höchstens zwei Koloskopien'),
        reason: 'the number of colonoscopies changed',
      );
      expect(
        bowel,
        contains('Eine Koloskopie ab dem Alter von 65 Jahren gilt als zweite'),
      );
      // The ten years are stated as the nine calendar years in which no
      // screening method may be used after one.
      expect(
        bowel,
        contains(
          'ist in den auf das Untersuchungsjahr folgenden neun '
          'Kalenderjahren keine Früherkennungsmethode anzuwenden',
        ),
      );

      expect((ruleNamed('colonoscopy').schedule as OnceFromAge).from.years, 50);
      final second = ruleNamed('colonoscopy-second').schedule as Booster;
      expect(second.after, 'colonoscopy');
      expect(second.every.years, 10);
      expect(
        second.repeats,
        1,
        reason: 'two in total means one after the first',
      );
    });

    test('cervical screening is yearly to 34 and every three years after', () {
      final first = RegExp(
        r'Frauen haben erstmalig ab dem Alter von (\d+) Jahren Anspruch',
      ).firstMatch(cervix);
      final cytology = RegExp(
        r'Im Alter von (\d+) bis (\d+) Jahren können Frauen jährlich das '
        r'zytologiebasierte',
      ).firstMatch(cervix);
      final cotest = RegExp(
        r'Ab dem Alter von (\d+) Jahren können Frauen alle (\w+) Jahre ein '
        r'kombiniertes',
      ).firstMatch(cervix);
      expect(
        first,
        isNotNull,
        reason: 'part III § 3 no longer reads as it did',
      );
      expect(cytology, isNotNull);
      expect(cotest, isNotNull);

      final yearly = ruleNamed('cervical-cytology');
      final schedule = yearly.schedule as Recurring;
      expect(schedule.from.years, int.parse(cytology!.group(1)!));
      expect(schedule.from.years, int.parse(first!.group(1)!));
      expect(schedule.every.years, 1);
      expect(schedule.until!.years, int.parse(cytology.group(2)!));
      expect(yearly.eligibility.sex, Sex.female);
      expect(
        yearly.eligibility.maxAge!.years,
        int.parse(cytology.group(2)!) + 1,
      );

      final combined = ruleNamed('cervical-cotest').schedule as Recurring;
      expect(combined.from.years, int.parse(cotest!.group(1)!));
      expect(cotest.group(2), 'drei');
      expect(combined.every.years, 3);
      expect(ruleNamed('cervical-cotest').eligibility.sex, Sex.female);
    });

    test('nothing else in the catalog claims this guideline', () {
      expect(rulesFrom('gba-okfe-rl'), {
        'cervical-cytology',
        'cervical-cotest',
        'colorectal-stool-test',
        'colonoscopy',
        'colonoscopy-second',
      });
    });
  });
}

/// One guideline, read section by section.
class _Guideline {
  _Guideline(String path) {
    // The table of contents repeats every heading with a page number after a
    // run of dots, and a heading found there would take the next heading's
    // text as its body.
    final lines = File(
      path,
    ).readAsLinesSync().where((l) => !l.contains('....')).toList();

    final heading = RegExp(r'^§\s*(\d+)\s*[a-z]?\s');
    var current = '';
    final body = StringBuffer();
    void flush() {
      if (current.isEmpty) return;
      _sections
          .putIfAbsent(current, () => [])
          .add(body.toString().replaceAll(RegExp(r'\s+'), ' ').trim());
    }

    for (final line in lines) {
      final match = heading.firstMatch(line);
      if (match != null) {
        flush();
        current = match.group(1)!;
        body.clear();
      }
      body.writeln(line);
    }
    flush();
  }

  final Map<String, List<String>> _sections = {};

  /// The body of `§ number`. Where a guideline has several parts with a
  /// section of the same number, [containing] picks the one that is about
  /// the right programme.
  String section(String number, {String? containing}) {
    final candidates = _sections[number] ?? const <String>[];
    expect(candidates, isNotEmpty, reason: 'no § $number in this guideline');
    if (containing == null) {
      expect(
        candidates,
        hasLength(1),
        reason: '§ $number appears more than once; say which one',
      );
      return candidates.single;
    }
    final matching = candidates.where((s) => s.contains(containing)).toList();
    expect(
      matching,
      hasLength(1),
      reason: 'no single § $number mentioning "$containing"',
    );
    return matching.single;
  }
}
