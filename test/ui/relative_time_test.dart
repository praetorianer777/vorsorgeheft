import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/l10n/app_localizations.dart';
import 'package:vorsorgeheft/ui/relative_time.dart';

void main() {
  final today = DateTime.utc(2026, 9, 20);

  Future<void> pumpRelative(
    WidgetTester tester,
    Locale locale,
    DateTime date,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(
            formatRelativeDate(AppLocalizations.of(context), date, today),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a window three weeks out reads as weeks in both languages', (
    tester,
  ) async {
    final date = today.add(const Duration(days: 21));

    await pumpRelative(tester, const Locale('en'), date);
    expect(find.text('in 3 weeks'), findsOneWidget);

    await pumpRelative(tester, const Locale('de'), date);
    expect(find.text('in 3 Wochen'), findsOneWidget);
  });

  testWidgets('the unit grows with the distance', (tester) async {
    await pumpRelative(tester, const Locale('en'), today);
    expect(find.text('today'), findsOneWidget);

    await pumpRelative(tester, const Locale('de'), today);
    expect(find.text('heute'), findsOneWidget);

    await pumpRelative(
      tester,
      const Locale('en'),
      today.add(const Duration(days: 1)),
    );
    expect(find.text('tomorrow'), findsOneWidget);

    await pumpRelative(
      tester,
      const Locale('de'),
      today.add(const Duration(days: 120)),
    );
    expect(find.text('in 4 Monaten'), findsOneWidget);

    await pumpRelative(
      tester,
      const Locale('en'),
      today.add(const Duration(days: 730)),
    );
    expect(find.text('in 2 years'), findsOneWidget);
  });

  testWidgets('a window already past reads as past', (tester) async {
    final date = today.subtract(const Duration(days: 21));

    await pumpRelative(tester, const Locale('en'), date);
    expect(find.text('3 weeks ago'), findsOneWidget);

    await pumpRelative(tester, const Locale('de'), date);
    expect(find.text('vor 3 Wochen'), findsOneWidget);
  });
}
