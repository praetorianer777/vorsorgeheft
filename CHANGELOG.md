# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versioning [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Bug fixes

- A person can be deleted again, from the edit form, after a confirmation.
  Their recorded appointments and reminders go with them, and the deletion
  reaches the other phone with the next sync.

### Other

- Tests now pin down what the suite left open: catalog invariants over every
  shipped catalog, the horizon and booster edge cases of the schedule engine,
  what a third phone does and does not receive, undo against a re-record, a
  peer removed and paired again, the reminder window topping up, a renamed
  person's calendar export, and end-to-end passes in German, through the
  edit form, over a school-age child's timeline, and against a file that is
  not a bundle.

## [0.2.1] - 2026-09-21

### Bug fixes

- The version shown in settings follows a release again: v0.2.0 still said
  0.1.0 because the release script did not rewrite that constant.

## [0.2.0] - 2026-09-21

### Features

- Reminders can be switched off, moved to another time of day, and set to
  fire 30, 14, 7, 3 or 1 days before a window opens and before an
  entitlement lapses, in settings. The choice stays on the phone it was made
  on; the "How this app works" screen states the chosen values.

### Features
- "Send to the other phone" seals the family under a six-digit code, shows
  the code and hands the file to the share sheet; "Receive from the other
  phone" opens it with that code. The `.vorsorge` file type is registered
  on Android and iOS so a received file opens the app. The password export
  stays for backups that are kept.
- The family can be given a name. It heads the start screen instead of
  "Family", reaches the other parent's phone with the next sync, and names the
  family's calendar export and the encrypted file.
- A "Report a problem" tile in settings opens a GitHub issue prefilled with
  app version, OS and language. Nothing leaves the phone until the person
  sends it.
- A phone that was never given a name introduces itself to the other one by
  its model, such as "Pixel 8" or "iPhone 15", instead of both showing up as
  "My phone". The pairing dialog says that the name is what the other phone
  will see.
- An icon of its own, a calendar leaf with a check mark in the app's green,
  on Android (adaptive) and iOS, in place of the Flutter default.
- A "How this app works" screen in settings explains, in plain words, where
  the appointments come from with the source documents linked, how the dates
  are worked out from the date of birth, what each status symbol means, when
  reminders fire, where the data lives and what happens when a guideline
  changes.
- When both phones recorded the same appointment, the later entry wins as
  before, but the phone whose entry was replaced now says so on its family
  screen until dismissed, naming the appointment, both dates and the device.
  The sync screen states the rule up front and suggests a hotspot when there
  is no shared Wi-Fi.

### Bug fixes
- The stored language is restored on start by a read nobody waits for; when
  it landed after the app's state was already torn down it threw into
  whatever ran next. It is now dropped instead.
- The dental examinations Z1 to Z6 lapse with their age span, as the U
  check-ups do: a child added later finds the ones that are over under "No
  longer available" instead of an "Overdue" that never clears.

### Other
- Every schema version ever shipped is recorded, and a test migrates each
  one to the current schema and checks the result against a fresh install;
  another fills a database the way v0.1.0 did and finds everything intact
  after the upgrade. The test gate refuses a changed table without a new
  schema dump, so a forgotten migration cannot ship.
- A bundle written in 2026 lives in the repo and every later version has to
  open it, so a family recorded today reaches the phone of ten years on. The
  end-to-end specs also run nightly on an iOS simulator.
- A device-only test schedules a reminder through the real notification
  plugin and reads it back from the shade, so the nightly emulator run proves
  a reminder is actually posted, not just planned.

## [0.1.0] - 2026-09-21

### Features

- A newborn added after the first days is offered to record the clinic
  examinations in one go, and the timeline says what to do next - how long is
  left, how long until a window opens - instead of when an entitlement opened.
  Overdue leads the list; each entry carries a status glyph.
- A one-time support prompt after the third recorded appointment, dismissible
  for good, plus a permanent link to the sponsor page in settings.
- Reminders before an appointment's window opens, and escalating warnings
  before an entitlement lapses. In German and English, at nine in the morning
  local time.
- Every change is recorded so two phones can be brought to the same state
  later without a server or an account. Edits made on both devices while apart
  are merged field by field, so renaming a child on one phone and recording an
  appointment on the other no longer costs one of the two.
- Keep a profile per family member and see their appointments on one timeline,
  grouped into what needs doing now, what is coming up, what is settled and
  what can no longer be had. Each appointment names the guideline it comes from
  and the date that guideline was last reviewed.
- Record an appointment as done or deliberately skipped, and undo it.
- German and English throughout, following the system language unless a
  language is picked in the new settings screen; that choice stays on the
  device it was made on. Dates and distances in time read in the chosen
  language, so a window opens "in 3 Wochen" or "in 3 weeks". The German
  designations U6, J1, Td and the rest are kept in the English text and
  explained where they are shown.
- Children's check-ups U1 to U9 and the J1, with the exclusion deadlines past
  which the entitlement lapses, plus the newborn, hearing, pulse-oximetry and
  cystic-fibrosis screenings. U10, U11 and J2 are included but flagged as
  depending on your insurer.
- Work out what is due for a person from their date of birth, covering one-off
  age windows with exclusion deadlines, recurring entitlements, one-off
  entitlements from an age, vaccination series whose doses depend on when the
  previous one was given, and boosters

### Other

- Set up the project scaffold, the test entry point and CI
- Cut releases with `./release.sh`: the version is derived from the commits
  since the last tag, written to `pubspec.yaml` and the Android config at once,
  and the tag carries the notes CI publishes. The APKs are signed with the
  keystore from the repository secrets, or debug-signed and marked a prerelease
  while those secrets are missing.
