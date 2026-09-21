# Privacy policy

As of 21 September 2026 · [Deutsche Fassung](datenschutz)

Vorsorgeheft is an app for Android and iOS that works out the preventive
care schedule for the members of a family and reminds you of it. It is built
to work without transmitting anything: there is no user account, no server,
no analytics or advertising service and no automatic crash reporting.

## Controller

<!-- Fill in before publishing: name and postal address. -->
The controller in the sense of the GDPR is the publisher of the app,
reachable through the contact address given in the app store or on
[GitHub](https://github.com/praetorianer777/vorsorgeheft/issues/new).

## What the app stores

Only what you enter yourself:

- family members with name, date of birth, optionally sex, and notes
- which check-ups and vaccinations were done or skipped, and when
- your settings (language, reminder times, family name)
- paired devices for sync (device name and keys)

This data lives only in the app's private storage on your device. It is not
transmitted to the publisher or to anyone else. No usage data, device
identifiers or location data are collected.

The appointments themselves are computed from the date of birth and the
catalogs shipped with the app; they are not stored.

## Permissions and what they are for

| Permission | Purpose |
|---|---|
| Notifications | Reminders for upcoming appointments, scheduled on the device |
| Run after reboot, exact alarms (Android) | Reschedule reminders after a restart and show them at the time you set |
| Camera | Only to scan the pairing code shown on the other phone; no images are stored |
| Local network, internet | Sync between two paired phones on the same Wi-Fi; the app connects to no server |
| Share files | Calendar export (ICS) and data transfer as a file, only when you trigger it |

## Sync between two phones

Sync runs directly from phone to phone. When pairing, the devices exchange
public keys through a QR code; everything is end-to-end encrypted with keys
derived from them. There is no relay server. When sending as a file, the
file is encrypted with a password only the two phones know.

## Calendar export

The ICS export produces a file with the appointments. Whatever you do with
it (import into a calendar, send by e-mail) is governed by the privacy
policy of that app.

## Report a problem

"Report a problem" opens a prepared form on GitHub in your browser, with
the app version and device model filled in. Nothing is sent unless you
submit it there; GitHub's
[privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)
applies.

## Links to sources

The app links to the guidelines of the Federal Joint Committee (G-BA) and
the recommendations of the STIKO. These open in your browser; from there
the privacy notices of those sites apply.

## Children's data

The app is typically used by parents and stores details about children.
These too stay on the device only.

## Deleting data

Delete a person in the app. Delete everything by uninstalling the app. On a
paired phone, the synced data stays until you delete it there as well.

## Your rights

Since no data reaches the publisher, there is nothing the publisher could
disclose, correct or erase. For questions, use the address above.

## Changes

This policy is maintained with the app. Its history is visible in the
[source repository](https://github.com/praetorianer777/vorsorgeheft/commits/main/docs/privacy.md).
