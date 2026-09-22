import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/ui/sync_screen.dart';

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
  Finder get defaultTitle => find.text('Family');
  Finder titled(String name) => find.text(name);

  /// Through the pencil, the same way the title itself opens the dialog.
  Future<void> rename(String name) async {
    await tester.tap(find.byKey(const Key('edit-family-name')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('family-name')), name);
    await tester.tap(find.byKey(const Key('family-name-ok')));
    await settle(tester);
  }

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
  Finder get catalogUpdate => find.byKey(const Key('catalog-update'));

  Future<void> dismissCatalogUpdate() async {
    await tester.tap(find.byKey(const Key('catalog-update-dismiss')));
    await settle(tester);
  }

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

  /// Types the date into the date dialog, in the order of the pinned English
  /// locale; the separators are the dialog's own.
  Future<void> pickDateOfBirth(String mmddyyyy) async {
    await tester.tap(find.byKey(const Key('pick-date-of-birth')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), mmddyyyy);
    await tester.tap(find.byKey(const Key('date-input-ok')));
    await settle(tester);
  }

  /// The optional vaccinations push the button below the fold, and the form
  /// only builds what is on screen. A save the form refuses leaves it open,
  /// scrolled to the bottom, so the top is brought back for the errors.
  Future<void> save() async {
    await _reveal(find.byKey(const Key('save-person')));
    await tester.tap(find.byKey(const Key('save-person')));
    await settle(tester);
    if (find.byKey(const Key('save-person')).evaluate().isNotEmpty) {
      await tester.drag(find.byType(ListView), const Offset(0, 4000));
      await settle(tester);
    }
  }

  /// Not [scrollTo]: the notes field is a Scrollable of its own, and
  /// `find.byType(Scrollable).last` would drag inside it instead of the form.
  Future<void> _reveal(Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await settle(tester);
  }

  Finder get deleteButton => find.byKey(const Key('delete-person'));

  Future<void> delete() async {
    await _reveal(deleteButton);
    await tester.tap(deleteButton);
    await settle(tester);
  }

  Future<void> confirmDelete() async {
    await tester.tap(find.byKey(const Key('confirm-delete-person')));
    await settle(tester);
  }

  Future<void> cancelDelete() async {
    await tester.tap(find.text('Cancel'));
    await settle(tester);
  }

  Finder get nameError => find.text('Please enter a name');
  Finder get dateError => find.text('Please pick a date of birth');

  Finder get optionalVaccinations => find.text('Optional vaccinations');
  Finder optionalSwitch(String ruleId) => find.byKey(Key('optional-$ruleId'));

  Future<void> toggleOptional(String ruleId) async {
    await _reveal(optionalSwitch(ruleId));
    await tester.tap(optionalSwitch(ruleId));
    await settle(tester);
  }

  Future<void> revealOptionalVaccinations() => _reveal(optionalVaccinations);

  /// The rule ids of every switch on the form, top to bottom. Walked rather
  /// than found in one go, since the list only builds what is on screen and
  /// "no switch for this rule" would otherwise be true of any rule below the
  /// fold.
  Future<List<String>> optionalSwitches() async {
    final seen = <String>[];
    void collect() {
      for (final tile in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        final id = (tile.key! as ValueKey<String>).value.substring(
          'optional-'.length,
        );
        if (!seen.contains(id)) seen.add(id);
      }
    }

    collect();
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('save-person')).evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await settle(tester);
      collect();
    }
    return seen;
  }
}

class TimelinePage {
  const TimelinePage(this.tester);

  final WidgetTester tester;

  Finder get needsAttention => find.text('Needs attention');
  Finder appointmentDates(String fragment) => find.textContaining(fragment);
  Finder get comingUp => find.text('Coming up');
  Finder get farAhead => find.text('Further ahead');
  Finder get settled => find.text('Done and skipped');
  Finder get noLongerAvailable => find.text('No longer available');
  Finder get germanNeedsAttention => find.text('Jetzt dran');
  Finder get germanComingUp => find.text('Demnächst');

  Future<PersonFormPage> edit() async {
    await tester.tap(find.byKey(const Key('edit-person')));
    await settle(tester);
    return PersonFormPage(tester);
  }

  /// The status word inside the tile titled [title], so that a spec can tell
  /// a Z1 that has lapsed from a Z4 that is still open without reading the
  /// whole list.
  Finder status(String title, String label) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    matching: find.text(label),
  );

  /// [scrollTo] stops as soon as the entry is built, which can be just below
  /// the screen; the tap needs it on screen.
  Future<AppointmentPage> open(String title) async {
    await scrollTo(tester, find.text(title));
    await tester.ensureVisible(find.text(title).first);
    await settle(tester);
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

  /// Not `pageBack`: it looks the back button up by its English tooltip,
  /// and the German pass walks back through this screen too.
  Future<void> back() async {
    await tester.tap(find.byType(BackButton));
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
  Finder get germanSource => find.textContaining('Quelle:');
  Finder get germanCatchUpBy => find.text('Nachholbar bis');
  Finder get germanMarkDone => find.text('Als erledigt erfassen');

  Future<void> markDone() async {
    await tester.tap(find.byKey(const Key('mark-done')));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  /// Records the appointment on a given day, typed into the date dialog in
  /// the order of the pinned English locale.
  Future<void> markDoneOn(String mmddyyyy) async {
    await tester.tap(find.byKey(const Key('mark-done')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('date-input')), mmddyyyy);
    await tester.tap(find.byKey(const Key('date-input-ok')));
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
    await tester.tap(find.byType(BackButton));
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

  Future<void> scrollToSupportLink() => scrollTo(tester, supportLink);
  Finder get reportProblem => find.byKey(const Key('report-problem'));
  Finder get remindersSwitch => find.byKey(const Key('reminders-enabled'));
  Finder reminderTime(String label) => find.text(label);

  Future<void> toggleReminders() async {
    await tester.tap(remindersSwitch);
    await settle(tester);
  }

  /// Drives the real time picker in its keyboard-input mode.
  Future<void> pickReminderTime({
    required int hour,
    required int minute,
  }) async {
    await tester.tap(find.byKey(const Key('reminders-time')));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '$hour');
    await tester.enterText(fields.at(1), '$minute');
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> toggleLead(int days) async {
    await tester.tap(find.byKey(Key('reminder-lead-$days')));
    await settle(tester);
  }

  Future<HowItWorksPage> openHowItWorks() async {
    await scrollTo(tester, find.byKey(const Key('open-how-it-works')));
    await tester.tap(find.byKey(const Key('open-how-it-works')));
    await settle(tester);
    return HowItWorksPage(tester);
  }

  Future<SourcesPage> openSources() async {
    await scrollTo(tester, find.byKey(const Key('open-sources')));
    await tester.tap(find.byKey(const Key('open-sources')));
    await settle(tester);
    return SourcesPage(tester);
  }

  Future<SyncPage> openSync() async {
    await scrollTo(tester, find.byKey(const Key('settings-open-sync')));
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
    await tester.ensureVisible(find.byKey(const Key('how-open-sources')));
    await settle(tester);
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
  Finder get germanTitle => find.text('Quellen & Rechtliches');
  Finder get germanDisclaimer => find.text('Keine ärztliche Beratung');
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
  Finder get notABundle => find.text('That is not a file this app exported.');
  Finder get addressPrompt => find.byKey(const Key('peer-address'));
  Finder unreachable(String name) =>
      find.text('$name could not be found on the network.');
  Finder imported(int count) =>
      find.text(count == 1 ? '1 change imported.' : '$count changes imported.');

  /// The name this phone offers the other one, read off the pairing dialog.
  Future<String> myName() async {
    await tester.tap(find.byKey(const Key('show-my-code')));
    await settle(tester);
    final name = tester
        .widget<TextField>(find.byKey(const Key('device-name')))
        .controller!
        .text;
    await tester.tap(find.byKey(const Key('close-my-code')));
    await settle(tester);
    return name;
  }

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

  /// Sends and returns the code the dialog shows, which is what the person
  /// would read out to the other parent. The file is written while the
  /// dialog is up, so the wait is the same as [exportBundle]'s.
  Future<String> sendToPhone(RecordingShareGateway share) async {
    final before = share.shared.length;
    await scrollTo(tester, find.byKey(const Key('send-to-phone')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('send-to-phone')));
      for (var i = 0; i < 500 && share.shared.length == before; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await settle(tester);
    final code = tester.widget<Text>(find.byKey(const Key('transfer-code')));
    await tester.tap(find.byKey(const Key('close-transfer-code')));
    await settle(tester);
    return code.data!;
  }

  Future<void> receiveFromPhone(
    SyncFixture sync,
    List<int> bytes, {
    required String code,
  }) async {
    sync.picker.nextFile = bytes;
    await scrollTo(tester, find.byKey(const Key('receive-from-phone')));
    await tester.tap(find.byKey(const Key('receive-from-phone')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('transfer-code-input')), code);
    await tester.tap(find.byKey(const Key('transfer-code-confirm')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
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
  await scrollTo(tester, find.byKey(button));
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
