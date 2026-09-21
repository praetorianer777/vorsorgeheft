import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/ui/sync_screen.dart';

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

  /// The family export lives in settings, with a label next to it: a share
  /// icon on the start screen reads as "share the app".
  Future<void> exportCalendar(RecordingShareGateway share) async {
    final settings = await openSettings();
    await tapExport(tester, share, const Key('export-ics'));
    await settings.back();
  }

  Finder get supportPrompt => find.byKey(const Key('support-prompt'));
  Finder get syncNotices => find.byKey(const Key('sync-notices'));

  Future<void> dismissSyncNotices() async {
    await tester.tap(find.byKey(const Key('sync-notices-dismiss')));
    await settle(tester);
  }

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
    final settings = await openSettings();
    return settings.openSources();
  }

  Future<SyncPage> openSync() async {
    await tester.tap(find.byKey(const Key('open-sync')));
    await settle(tester);
    return SyncPage(tester);
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

  /// The status word inside the tile titled [title], so that a spec can tell
  /// a Z1 that has lapsed from a Z4 that is still open without reading the
  /// whole list.
  Finder status(String title, String label) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    matching: find.text(label),
  );

  Future<AppointmentPage> open(String title) async {
    await scrollTo(tester, find.text(title));
    await tester.tap(find.text(title).first);
    await settle(tester);
    return AppointmentPage(tester);
  }

  Future<void> scrollToAppointment(String title) =>
      scrollTo(tester, find.text(title));

  Future<void> exportCalendar(RecordingShareGateway share) =>
      tapExport(tester, share, const Key('export-person-ics'));

  Finder get clinicOffer => find.byKey(const Key('clinic-offer'));

  Future<void> acceptClinicOffer() async {
    await tester.tap(find.byKey(const Key('clinic-offer-accept')));
    await settle(tester);
  }

  Future<void> dismissClinicOffer() async {
    await tester.tap(find.byKey(const Key('clinic-offer-dismiss')));
    await settle(tester);
  }

  /// The titles in the order they are on screen right now.
  List<String> visibleTitles() => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title as Text).data ?? '')
      .toList();

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

  /// Records the appointment on a given day, through the date picker's
  /// keyboard mode, in the format of the pinned English locale.
  Future<void> markDoneOn(String mmddyyyy) async {
    await tester.tap(find.byKey(const Key('mark-done')));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, mmddyyyy);
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
  Finder get version => find.textContaining(RegExp('^Version '));

  /// The version sits at the end of the list, below the fold on a phone.
  Future<void> scrollToVersion() async {
    await tester.scrollUntilVisible(version, 200);
    await settle(tester);
  }

  Future<void> scrollToReportProblem() async {
    await tester.scrollUntilVisible(reportProblem, 200);
    await settle(tester);
  }

  Future<void> chooseGerman() => _choose('language-de');
  Future<void> chooseEnglish() => _choose('language-en');
  Future<void> chooseSystemLanguage() => _choose('language-system');

  Future<void> _choose(String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Finder get supportLink => find.byKey(const Key('support-link'));
  Finder get reportProblem => find.byKey(const Key('report-problem'));

  Future<HowItWorksPage> openHowItWorks() async {
    await scrollTo(tester, find.byKey(const Key('open-how-it-works')));
    await tester.tap(find.byKey(const Key('open-how-it-works')));
    await settle(tester);
    return HowItWorksPage(tester);
  }

  Future<SourcesPage> openSources() async {
    await tester.tap(find.byKey(const Key('open-sources')));
    await settle(tester);
    return SourcesPage(tester);
  }

  Future<SyncPage> openSync() async {
    await tester.tap(find.byKey(const Key('settings-open-sync')));
    await settle(tester);
    return SyncPage(tester);
  }

  /// Not `pageBack`: it looks the back button up by its English tooltip, and
  /// this is the one screen that can change the language under itself.
  Future<void> back() async {
    await tester.tap(find.byType(BackButton));
    await settle(tester);
  }
}

class HowItWorksPage {
  const HowItWorksPage(this.tester);

  final WidgetTester tester;

  Finder get title => find.text('How this app works');
  Finder get germanTitle => find.text('So funktioniert die App');
  Finder section(String title) => find.text(title);
  Finder sourceLink(String url) => find.textContaining(url);
  Finder get legendOverdue => find.textContaining('Overdue: ');
  Finder get reminders => find.textContaining('30, 14, 3 days before');

  Future<void> reveal(Finder finder) => scrollTo(tester, finder);

  Future<SourcesPage> openSources() async {
    await scrollTo(tester, find.byKey(const Key('how-open-sources')));
    await tester.tap(find.byKey(const Key('how-open-sources')));
    await settle(tester);
    return SourcesPage(tester);
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

class SyncPage {
  const SyncPage(this.tester);

  final WidgetTester tester;

  Finder get title => find.text('Sync');
  Finder get noDevices => find.byKey(const Key('no-peers'));
  Finder deviceNamed(String name) => find.text(name);
  Finder get neverSynced => find.text('Never synced');
  Finder get lastSynced => find.textContaining('Last synced');
  Finder get nothingNew => find.text('Nothing to send, nothing new.');
  Finder synced({required int received, required int sent}) =>
      find.text('Received $received and sent $sent changes.');
  Finder pairedWith(String name) => find.text('Paired with $name.');
  Finder get invalidCode =>
      find.text('That is not a pairing code of this app.');
  Finder get wrongPassword =>
      find.text('Wrong password, or the file was altered.');
  Finder get addressPrompt => find.byKey(const Key('peer-address'));
  Finder unreachable(String name) =>
      find.text('$name could not be found on the network.');
  Finder imported(int count) =>
      find.text(count == 1 ? '1 change imported.' : '$count changes imported.');

  /// Opens the pairing dialog and returns the code the QR image carries,
  /// which is what the other phone's camera would read.
  Future<String> showMyCode({String? deviceName}) async {
    await tester.tap(find.byKey(const Key('show-my-code')));
    await settle(tester);
    if (deviceName != null) {
      await tester.enterText(find.byKey(const Key('device-name')), deviceName);
      await settle(tester);
      // The name is part of the code, so the dialog is opened once more to
      // read the code that carries it.
      await tester.tap(find.byKey(const Key('close-my-code')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('show-my-code')));
      await settle(tester);
    }
    final code = tester
        .widget<PairingCodeImage>(find.byKey(const Key('pairing-code')))
        .code;
    await tester.tap(find.byKey(const Key('close-my-code')));
    await settle(tester);
    return code;
  }

  /// Scans whatever the fixture's camera has been handed.
  Future<void> scanCode(SyncFixture sync, String code) async {
    sync.scanner.nextCode = code;
    await tester.tap(find.byKey(const Key('scan-code')));
    await settle(tester);
  }

  Future<void> syncNow(String peerNodeId) async {
    await tester.tap(find.byKey(Key('sync-now-$peerNodeId')));
    await settle(tester);
    await settle(tester);
  }

  Future<void> enterAddress(String address) async {
    await tester.enterText(addressPrompt, address);
    await tester.tap(find.byKey(const Key('connect')));
    await settle(tester);
    await settle(tester);
  }

  Future<void> removeDevice(String peerNodeId) async {
    await tester.tap(find.byKey(Key('remove-peer-$peerNodeId')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-remove-peer')));
    await settle(tester);
  }

  /// Exports and waits for the file to actually be written, the same way
  /// [tapExport] does for the calendar.
  Future<void> exportBundle(
    RecordingShareGateway share, {
    required String password,
  }) async {
    final before = share.shared.length;
    await scrollTo(tester, find.byKey(const Key('export-bundle')));
    await tester.tap(find.byKey(const Key('export-bundle')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('bundle-password')), password);
    // Unlike the calendar export, the confirmation pops a dialog, and that
    // needs frames before the export even starts; the frames are pumped from
    // inside runAsync so the file write that follows can complete too.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('bundle-confirm')));
      for (var i = 0; i < 500 && share.shared.length == before; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await settle(tester);
  }

  Future<void> importBundle(
    SyncFixture sync,
    List<int> bytes, {
    required String password,
  }) async {
    sync.picker.nextFile = bytes;
    await scrollTo(tester, find.byKey(const Key('import-bundle')));
    await tester.tap(find.byKey(const Key('import-bundle')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('bundle-password')), password);
    await tester.tap(find.byKey(const Key('bundle-confirm')));
    // Stretching the password pauses every couple of thousand rounds to let
    // the UI breathe, and each pause is a timer the pumped clock has to pass.
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
  }

  Future<void> back() async {
    await tester.pageBack();
    await settle(tester);
  }
}

/// Exports and waits for the file to actually be written.
///
/// Writing it is real I/O, which a pumped frame does not advance: under the
/// headless binding the clock is fake, and only `runAsync` lets the event loop
/// deliver the completion.
Future<void> tapExport(
  WidgetTester tester,
  RecordingShareGateway share,
  Key button,
) async {
  final before = share.shared.length;
  // The tap itself happens inside runAsync: under the headless binding the
  // continuations of the export would otherwise be queued on the fake clock,
  // which nothing advances while the real file is being written.
  await tester.runAsync(() async {
    await tester.tap(find.byKey(button));
    for (var i = 0; i < 200 && share.shared.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await settle(tester);
}
