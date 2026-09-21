# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versioning [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Features

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
- German and English throughout.
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
