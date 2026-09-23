# Datenschutzerklärung

Stand: 21. September 2026 · [English version](privacy)

Vorsorgeheft ist eine App für Android und iOS, die Vorsorgetermine für
Familienmitglieder berechnet und daran erinnert. Sie wurde so gebaut, dass
sie ohne Datenübertragung auskommt: Es gibt kein Benutzerkonto, keinen
Server, keine Analyse- oder Werbedienste und keine automatische Fehlermeldung.

## Verantwortlicher

<!-- Vor der Veröffentlichung eintragen: Name und Anschrift. -->
Verantwortlich im Sinne der DSGVO ist der Herausgeber der App, erreichbar über
die im App-Store angegebene Kontaktadresse oder über
[GitHub](https://github.com/praetorianer777/vorsorgeheft/issues/new).

## Welche Daten die App speichert

Die App speichert nur, was du selbst eingibst:

- Familienmitglieder mit Name, Geburtsdatum, optional Geschlecht und Notizen
- welche Untersuchungen und Impfungen wann erledigt oder übersprungen wurden
- deine Einstellungen (Sprache, Erinnerungszeiten, Familienname)
- gekoppelte Geräte für den Abgleich (Gerätename und Schlüssel)

Diese Daten liegen ausschließlich im privaten Speicher der App auf deinem
Gerät. Sie werden weder an den Herausgeber noch an Dritte übertragen. Es
werden keine Nutzungsdaten, Gerätekennungen oder Standortdaten erhoben.

Die Vorsorgetermine selbst werden aus Geburtsdatum und den in der App
hinterlegten Katalogen berechnet und nicht gespeichert.

## Systembackup und Umzug auf ein neues Telefon

Die App ist vom Cloud-Backup des Betriebssystems ausgenommen. Google und
Apple erhalten also keine Kopie deiner Daten.

Richtest du ein neues Telefon direkt vom alten ein (Geräteumzug bei Android,
Schnellstart bei iOS), werden die Daten dabei übertragen; das läuft von
Gerät zu Gerät und über keinen Server. Auf Android 11 und älter lässt sich
beides technisch nicht trennen, dort wird gar nichts gesichert — der Weg auf
ein neues Telefon ist dann der Abgleich oder die verschlüsselte Datei.

Bis einschließlich Version 0.6.1 hat Android die Daten in das Google-Konto
gesichert. Eine solche ältere Sicherung löschst du in den Google-One-
Einstellungen unter „Sicherung" bei den App-Daten.

## Berechtigungen und wofür sie gebraucht werden

| Berechtigung | Zweck |
|---|---|
| Benachrichtigungen | Erinnerungen an anstehende Termine, geplant auf dem Gerät |
| Start nach Neustart, exakte Alarme (Android) | Erinnerungen nach einem Neustart neu planen und zur eingestellten Uhrzeit zeigen |
| Kamera | Nur zum Scannen des Kopplungscodes vom anderen Telefon; es werden keine Bilder gespeichert |
| Lokales Netzwerk, Internet | Abgleich zwischen zwei gekoppelten Telefonen im selben WLAN; die App verbindet sich mit keinem Server |
| Dateien teilen | Kalenderexport (ICS) und Datenübertragung als Datei, nur wenn du es auslöst |

## Abgleich zwischen zwei Telefonen

Der Abgleich läuft direkt von Telefon zu Telefon. Beim Koppeln tauschen die
Geräte über einen QR-Code öffentliche Schlüssel aus; alle Daten werden davon
abgeleitet Ende-zu-Ende verschlüsselt. Es gibt keinen Vermittlungsserver.
Beim Senden als Datei ist die Datei mit einem Passwort verschlüsselt, das
nur die beiden Telefone kennen.

## Kalenderexport

Der ICS-Export erzeugt eine Datei mit den Terminen. Was du damit machst
(in einen Kalender importieren, per E-Mail verschicken), unterliegt den
Datenschutzbestimmungen der jeweiligen App.

## Problem melden

„Problem melden" öffnet im Browser ein vorbereitetes Formular auf GitHub mit
App-Version und Gerätemodell. Gesendet wird nur, was du dort selbst
abschickst; dafür gilt die
[Datenschutzerklärung von GitHub](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Links zu Quellen

Die App verlinkt auf die Richtlinien des Gemeinsamen Bundesausschusses und
die Empfehlungen der STIKO. Diese Links öffnen im Browser; ab dort gelten
die Datenschutzhinweise der jeweiligen Seite.

## Daten von Kindern

Die App wird typischerweise von Eltern genutzt und speichert Angaben zu
Kindern. Auch diese bleiben ausschließlich auf dem Gerät.

## Löschen

Einzelne Personen löschst du in der App. Alle Daten löschst du, indem du
die App deinstallierst. Auf einem gekoppelten Telefon bleiben die dort
abgeglichenen Daten, bis du sie dort ebenfalls löschst.

## Deine Rechte

Da keine Daten an den Herausgeber übertragen werden, liegt ihm nichts vor,
worüber er Auskunft geben, was er berichtigen oder löschen könnte. Bei
Fragen erreichst du ihn über die oben genannte Adresse.

## Änderungen

Diese Erklärung wird mit der App gepflegt. Ihre Versionsgeschichte ist im
[Quellcode](https://github.com/praetorianer777/vorsorgeheft/commits/main/docs/datenschutz.md)
einsehbar.
