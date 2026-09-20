# 🩺 Vorsorgereminder

Preventive-care appointments in Germany come with fixed time windows — and for children's
check-ups those windows are **hard deadlines**: a U6 caught up after the 14th month of life is no
longer covered and comes out of your own pocket. STIKO vaccinations depend on minimum intervals
between doses, and from 35 onwards hardly anyone knows the intervals for the general check-up or
skin-cancer screening.

Vorsorgereminder keeps a profile per family member, derives the full preventive-care schedule from
the date of birth, and reminds you in time.

- 👨‍👩‍👧 **Per family member** — from newborn to grandparent
- 📅 **Four catalogs** — children's check-ups U1–U9/J1, the STIKO vaccination calendar, dental
  care, and adult and cancer screening
- 🔒 **Entirely local** — no account, no servers, no analytics, no ads
- 📤 **ICS export** — into any calendar or mail client, with stable UIDs instead of duplicates
- 🔄 **Two devices, one state** — QR pairing, then encrypted sync over your WLAN
- 📚 **Sourced** — every appointment names its source and its as-of date, right in the app
- 🔔 **Reminders** — 30, 14 and 3 days before a window opens, and again before an entitlement lapses
- 🌍 **Bilingual** — the app speaks German and English

> **Status:** under development. There is no release yet.

## Why another app

Health-insurer apps cover parts of this, but only for their own members and only by handing the
data to the insurer. Vaccination-passport apps handle vaccinations but neither children's
check-ups nor adult screening. The [official STIKO app by the RKI][stiko-app] targets medical
professionals — a personal reminder calendar is explicitly not part of it. The closest match is
[APPzumARZT][appzumarzt], which also keeps all data on the device, but is closed source, offers
neither calendar export nor device-to-device sync, and ships bundled with sponsored content.

## Installation

Signed APKs will appear under [Releases](https://github.com/praetorianer777/vorsorgereminder/releases).
iOS is built and tested, but not distributed yet.

## Catalogs and sources

The catalogs live as versioned JSON files in [`assets/catalogs/`](assets/catalogs/). Every rule
carries a source reference with an as-of date, shown in the app both on the appointment's detail
page and collected under "Sources & legal". A test fails as soon as a rule without a resolvable
source enters a catalog — the sourcing requirement is enforced by CI, not by discipline.

All catalogs describe the German statutory system; rule text is stored per language so the app can
present it in German or English.

| Catalog | Contents | Source |
|---|---|---|
| Children's check-ups | U1–U9 incl. U7a and J1, with time windows **and** tolerance limits; newborn, hearing, pulse-oximetry and cystic-fibrosis screening | [G-BA Kinder-Richtlinie][gba-kinder] |
| Vaccinations | Vaccination calendar: standard immunisations from infant to adult, minimum intervals, boosters | [STIKO recommendations][stiko] |
| Dental care | Z1–Z6 for the first six years, individual prophylaxis from 6 to 17, one adult check-up per calendar year | [G-BA FU-Richtlinie][gba-zahn], [IP-Richtlinie][gba-ip], [§ 55 SGB V][sgb55] |
| Adult check-up | Once between 18 and 34, then every three years from 35; hepatitis B/C screening; abdominal aortic aneurysm | [G-BA Gesundheitsuntersuchungs-Richtlinie][gba-gu] |
| Cancer screening | Skin from 35, cervical from 20, mammography 50–75, prostate from 45, chlamydia to 25 | [G-BA Krebsfrüherkennungs-Richtlinie][gba-kfe] |
| Organised programmes | Cervical co-test from 35 and colorectal screening from 50, which moved into their own guideline | [G-BA oKFE-Richtlinie][gba-okfe] |

Two things are deliberately missing. The lung cancer screening is only for heavy smokers, and the
app does not ask about smoking; indication-based vaccinations depend on illness, occupation,
pregnancy or travel, none of which the app knows. A reminder for either would be wrong for almost
everyone who saw it.

Services that are **not** statutory (U10, U11, J2, professional tooth cleaning) are labelled
"depends on your insurer" in the app. `catalog-watch.yml` checks nightly whether one of the source
documents has changed and files an issue if so.

## Calendar export

Every appointment can be exported as an `.ics` file, for one person or for the whole family, and
handed to any calendar or mail client. Events are all-day and cover the window the appointment
falls in; the exclusion deadline, the source and the link to the guideline are in the description,
and alarms mirror the in-app reminders.

Each event keeps a stable UID across exports, so importing a newer file **updates** the events
instead of adding a second copy of each. An appointment that has been recorded or has lapsed since
the last export is written out as a cancellation, because an import can only add and update - an
event that was simply left out would stay in the calendar forever.

## Device sync

Both devices exchange public keys once via QR code and derive a shared key from them
(X25519 → HKDF); the private half never leaves the device. After that they find each other over
mDNS on the same WLAN and exchange only the changes since the last sync, encrypted with
AES-256-GCM. There is no server and no account. Without a shared WLAN, you export a
password-encrypted file instead.

## Privacy

The app stores data locally only, needs no network access beyond the LAN sync, and sends no
telemetry. There is no account and no operator who could see anything.

## Building

Requires a Flutter SDK on the stable channel with Dart ≥ 3.10.

```bash
flutter pub get
flutter run                  # debug build on an attached device
flutter run -d linux         # development target, for looking at the app quickly
flutter build apk --release  # release APK
```

The `linux/` target exists so the app can be run and driven on a development
machine without an emulator. It is not shipped and is not built in CI.

## Testing

| Suite | How | What it covers |
|---|---|---|
| Everything | `./run-tests.sh` | The single entry point. The branch-guard hook runs it before every push, and `ci.yml` has no other step. |
| Shell | `./tests/test-release.sh`, `./.claude/hooks/tests/branch-guard-test.sh` | Release script and branch guard, offline and without Flutter |
| Format & analysis | `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos` | |
| Unit | `flutter test` | Due-date engine, catalog validation incl. the source requirement, data layer, UI flows |
| End-to-end | `flutter test` | The specs in `integration_test/specs.dart`, run headless so they gate every push |
| End-to-end on a device | `ANDROID_E2E=1 ./run-tests.sh` | The same specs on an emulator or device, where platform channels and the real asset bundle are in play; runs nightly in CI |

The end-to-end specs are written once and run under two bindings. A spec that
only ever ran on the emulator would be written and then left to rot, because
nobody waits four minutes for an emulator before pushing.

## Continuous integration

The principle: everything fast and offline gates the PR, everything slow or network-dependent runs
at night.

| Workflow | When | What |
|---|---|---|
| `ci.yml` | PR, push to `main`, nightly | runs nothing but `run-tests.sh` |
| `release.yml` | tag `v*` | builds and signs the APKs and publishes them idempotently as a release |
| `ios-build.yml` | nightly | `flutter build ios --no-codesign` — keeps iOS compiling |
| `android-e2e.yml` | nightly | integration tests on the emulator |
| `catalog-watch.yml` | nightly | checks whether a guideline source has changed |

## Contributing

Every change hangs off an issue and a branch named `<type>/<issue>-<slug>`, and lands via pull
request. Details in [`.claude/skills/gh/SKILL.md`](.claude/skills/gh/SKILL.md).

## ⚠️ Disclaimer

This app is not medical advice. Its data is taken from the guidelines listed above, as of the
dates given there, and comes without warranty. Entitlements change and vary between insurers —
when in doubt, ask your doctor's office or your health insurer.

## License

[GPL-3.0](LICENSE)

[stiko-app]: https://www.rki.de/DE/Themen/Infektionskrankheiten/Impfen/Staendige-Impfkommission/STIKO-App/stiko-app-node.html
[appzumarzt]: https://www.felix-burda-stiftung.de/appzumarzt
[gba-kinder]: https://www.g-ba.de/richtlinien/15/
[stiko]: https://www.rki.de/DE/Themen/Infektionskrankheiten/Impfen/Impfkalender/impfkalender-node.html
[gba-zahn]: https://www.g-ba.de/richtlinien/29/
[gba-gu]: https://www.g-ba.de/richtlinien/10/
[gba-kfe]: https://www.g-ba.de/richtlinien/17/
[gba-okfe]: https://www.g-ba.de/richtlinien/104/
[gba-ip]: https://www.g-ba.de/richtlinien/31/
[sgb55]: https://www.gesetze-im-internet.de/sgb_5/__55.html
