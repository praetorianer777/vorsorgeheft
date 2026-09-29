import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// Holds the two seasonal vaccinations to the footnote they come from.
///
/// The STIKO calendar gives influenza and COVID-19 as a season rather than
/// as an interval, and the catalog used to model them as a year from the
/// person's birthday - which told somebody born in April to have a flu shot
/// in April. The footnote is one line and it is the whole basis for the
/// dates, so it is worth reading rather than remembering.
void main() {
  final calendar = File('tools/catalog-sources/stiko-impfkalender.txt')
      .readAsStringSync()
      .replaceAll(RegExp(r'-[ \t]*\r?\n\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final catalog = catalogNamed('vaccinations');

  Seasonal seasonOf(String id) =>
      catalog.rules.singleWhere((r) => r.id == id).schedule as Seasonal;

  test('the calendar still gives them as one per season', () {
    expect(
      calendar,
      contains(
        'Jährliche Impfung (einmalig pro Saison) im Herbst (COVID-19) bzw. '
        'Herbst/Winter (Influenza)',
      ),
      reason: 'footnote m no longer reads as it did',
    );
  });

  test('influenza runs through the winter, COVID-19 only the autumn', () {
    // The footnote's own distinction: Herbst/Winter against Herbst.
    for (final id in ['influenza', 'influenza-under-60']) {
      expect(seasonOf(id).spansNewYear, isTrue, reason: id);
      expect(seasonOf(id).closes.month, 1, reason: id);
    }
    for (final id in ['covid', 'covid-under-75']) {
      expect(seasonOf(id).spansNewYear, isFalse, reason: id);
      expect(seasonOf(id).closes.month, 11, reason: id);
    }
  });

  test('all four open with October, not with a birthday', () {
    for (final id in [
      'influenza',
      'influenza-under-60',
      'covid',
      'covid-under-75',
    ]) {
      expect(seasonOf(id).opens.month, 10, reason: id);
      expect(seasonOf(id).opens.day, 1, reason: id);
    }
  });

  test('nothing else in the catalog is seasonal', () {
    // A vaccination given by season and modelled as an interval is the bug
    // this replaced; a new one should have to come past this list.
    expect(
      catalog.rules
          .where((r) => r.schedule is Seasonal)
          .map((r) => r.id)
          .toSet(),
      {'influenza', 'influenza-under-60', 'covid', 'covid-under-75'},
    );
  });
}
