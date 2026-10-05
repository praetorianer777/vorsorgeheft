import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/domain/schedule.dart';

import '../support/catalogs.dart';

/// The "Data or code" section of the README argues from two numbers: how
/// many rules there are and how many kinds of schedule they are built from.
/// An argument that rests on a number nobody maintains stops being an
/// argument, so the numbers are read back out of the catalogs here.
void main() {
  // The prose is wrapped, so a sentence the section makes spans two lines.
  final readme = File(
    'README.md',
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final catalogs = shippedCatalogs();

  test('the README still has the section these numbers belong to', () {
    expect(readme, contains('### Data or code'));
  });

  test('it says how many rules there are', () {
    final rules = catalogs.catalogs.fold<int>(
      0,
      (total, catalog) => total + catalog.rules.length,
    );
    expect(
      readme,
      contains('moving $rules rules into Dart'),
      reason: 'the catalogs now carry $rules rules',
    );
  });

  test('it says how many kinds of schedule they are built from', () {
    final kinds = {
      for (final rule in catalogs.rules) rule.schedule.runtimeType,
    };
    const spelled = {
      4: 'Four',
      5: 'Five',
      6: 'Six',
      7: 'Seven',
      8: 'Eight',
      9: 'Nine',
    };
    // RecurringFromDate is never read from a catalog: a person's own
    // appointment is built in code and has no JSON form.
    expect(kinds, isNot(contains(RecurringFromDate)));
    expect(
      readme,
      contains('${spelled[kinds.length]} schedule types is the vocabulary'),
      reason: 'the catalogs now use ${kinds.length} kinds: $kinds',
    );
  });
}
