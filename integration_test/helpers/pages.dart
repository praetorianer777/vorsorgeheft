import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/recording_share.dart';
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

  Future<void> exportCalendar(RecordingShareGateway share) =>
      tapExport(tester, share);

  Finder get supportPrompt => find.byKey(const Key('support-prompt'));

  Future<void> dismissSupportPrompt() async {
    await tester.tap(find.byKey(const Key('support-prompt-dismiss')));
    await settle(tester);
  }

  Future<SettingsPage> openSettings() async {
    await tester.tap(find.byKey(const Key('open-settings')));
    await settle(tester);
    return SettingsPage(tester);
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
  Finder appointmentDates(String fragment) => find.textContaining(fragment);
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

  Future<void> exportCalendar(RecordingShareGateway share) =>
      tapExport(tester, share);

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

class SettingsPage {
  const SettingsPage(this.tester);

  final WidgetTester tester;

  Finder get title => find.text('Settings');
  Finder get germanTitle => find.text('Einstellungen');
  Finder get version => find.textContaining('Version ');

  Future<void> chooseGerman() => _choose('language-de');
  Future<void> chooseEnglish() => _choose('language-en');
  Future<void> chooseSystemLanguage() => _choose('language-system');

  Future<void> _choose(String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Finder get supportLink => find.byKey(const Key('support-link'));

  Future<SourcesPage> openSources() async {
    await tester.tap(find.byKey(const Key('open-sources')));
    await settle(tester);
    return SourcesPage(tester);
  }

  /// Not `pageBack`: it looks the back button up by its English tooltip, and
  /// this is the one screen that can change the language under itself.
  Future<void> back() async {
    await tester.tap(find.byType(BackButton));
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

/// Exports and waits for the file to actually be written.
///
/// Writing it is real I/O, which a pumped frame does not advance: under the
/// headless binding the clock is fake, and only `runAsync` lets the event loop
/// deliver the completion.
Future<void> tapExport(WidgetTester tester, RecordingShareGateway share) async {
  final before = share.shared.length;
  // The tap itself happens inside runAsync: under the headless binding the
  // continuations of the export would otherwise be queued on the fake clock,
  // which nothing advances while the real file is being written.
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('export-ics')));
    for (var i = 0; i < 200 && share.shared.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await settle(tester);
}
