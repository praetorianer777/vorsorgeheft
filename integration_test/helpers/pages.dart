import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Page objects, so a spec reads as behaviour rather than as widget finders.
///
/// Every finder the suite depends on lives here: when a screen is rearranged,
/// this file is the only thing that has to follow.
class FamilyPage {
  const FamilyPage(this.tester);

  final WidgetTester tester;

  Finder get emptyState => find.text('No one here yet');
  Finder personNamed(String name) => find.text(name);

  Future<PersonFormPage> addPerson() async {
    await tester.tap(find.byKey(const Key('add-person')));
    await settle(tester);
    return PersonFormPage(tester);
  }

  Future<TimelinePage> open(String name) async {
    await tester.tap(personNamed(name));
    await settle(tester);
    return TimelinePage(tester);
  }

  Future<SourcesPage> openSources() async {
    await tester.tap(find.byIcon(Icons.info_outline));
    await settle(tester);
    return SourcesPage(tester);
  }
}

class PersonFormPage {
  const PersonFormPage(this.tester);

  final WidgetTester tester;

  Future<void> enterName(String name) async {
    await tester.enterText(find.byKey(const Key('person-name')), name);
    await settle(tester);
  }

  /// Drives the real date picker in its keyboard-input mode. The format is the
  /// one the pinned English locale uses.
  Future<void> pickDateOfBirth(String mmddyyyy) async {
    await tester.tap(find.byKey(const Key('pick-date-of-birth')));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, mmddyyyy);
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> save() async {
    await tester.tap(find.byKey(const Key('save-person')));
    await settle(tester);
  }

  Finder get nameError => find.text('Please enter a name');
  Finder get dateError => find.text('Please pick a date of birth');
}

class TimelinePage {
  const TimelinePage(this.tester);

  final WidgetTester tester;

  Finder get needsAttention => find.text('Needs attention');
  Finder get comingUp => find.text('Coming up');
  Finder get settled => find.text('Done and skipped');
  Finder get noLongerAvailable => find.text('No longer available');

  Future<AppointmentPage> open(String title) async {
    await scrollTo(tester, find.text(title));
    await tester.tap(find.text(title).first);
    await settle(tester);
    return AppointmentPage(tester);
  }

  Future<void> scrollToAppointment(String title) =>
      scrollTo(tester, find.text(title));

  Future<void> back() async {
    await tester.pageBack();
    await settle(tester);
  }
}

class AppointmentPage {
  const AppointmentPage(this.tester);

  final WidgetTester tester;

  Finder get status => find.byType(Text);
  Finder statusText(String label) => find.text(label);
  Finder get source => find.textContaining('Source:');
  Finder get catchUpBy => find.text('Catch up by');

  Future<void> markDone() async {
    await tester.tap(find.byKey(const Key('mark-done')));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> markSkipped() async {
    await tester.tap(find.byKey(const Key('mark-skipped')));
    await settle(tester);
  }

  Future<void> undo() async {
    await tester.tap(find.byKey(const Key('undo-record')));
    await settle(tester);
  }

  Future<void> back() async {
    await tester.pageBack();
    await settle(tester);
  }
}

class SourcesPage {
  const SourcesPage(this.tester);

  final WidgetTester tester;

  Finder get disclaimer => find.text('This is not medical advice');
  Finder get privacy => find.text('Your data stays here');
  Finder sourceNamed(String fragment) => find.textContaining(fragment);

  Future<void> scrollToDisclaimer() => scrollTo(tester, disclaimer);
}
