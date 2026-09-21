import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgereminder/l10n/app_localizations.dart';
import 'package:vorsorgereminder/ui/date_input.dart';

TextEditingValue _type(
  DateSeparatorFormatter formatter,
  String before,
  String after,
) => formatter.formatEditUpdate(
  TextEditingValue(text: before),
  TextEditingValue(text: after),
);

void main() {
  group('DateSeparatorFormatter', () {
    const dot = DateSeparatorFormatter('.');

    test('puts the separators in as the digits arrive', () {
      expect(_type(dot, '', '0').text, '0');
      expect(_type(dot, '0', '01').text, '01');
      expect(_type(dot, '01', '019').text, '01.9');
      expect(_type(dot, '01.9', '01.90').text, '01.90');
      expect(_type(dot, '01.90', '01.902').text, '01.90.2');
      expect(_type(dot, '01.90.202', '01.90.2026').text, '01.90.2026');
    });

    test('stops at eight digits', () {
      expect(_type(dot, '01.09.2026', '01.09.20261').text, '01.09.2026');
    });

    test('accepts a date pasted with its own separators', () {
      expect(_type(dot, '', '1/9/2026').text, '19.20.26');
      expect(_type(dot, '', '01/09/2026').text, '01.09.2026');
    });

    test('backspace over a separator takes the digit before it', () {
      expect(_type(dot, '01.09', '01.0').text, '01.0');
      expect(_type(dot, '01.0', '01.').text, '01');
    });

    test('keeps the caret at the end', () {
      final value = _type(dot, '01', '019');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('uses the locale separator', () {
      expect(
        _type(const DateSeparatorFormatter('/'), '', '09012026').text,
        '09/01/2026',
      );
    });
  });

  group('dateSeparatorOf', () {
    Future<MaterialLocalizations> load(Locale locale) =>
        GlobalMaterialLocalizations.delegate.load(locale);

    test('a prefilled date carries its leading zeros', () async {
      final date = DateTime.utc(2024, 2, 9);
      expect(prefilledDate(await load(const Locale('de')), date), '09.02.2024');
      expect(prefilledDate(await load(const Locale('en')), date), '02/09/2024');
    });

    test('is a dot for German and a slash for English', () async {
      expect(dateSeparatorOf(await load(const Locale('de'))), '.');
      expect(dateSeparatorOf(await load(const Locale('en'))), '/');
    });
  });

  group('showDateInputDialog', () {
    Future<DateTime?> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      DateTime? initialDate,
    }) async {
      DateTime? result;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = true;
                result = await showDateInputDialog(
                  context: context,
                  initialDate: initialDate,
                  firstDate: DateTime.utc(2020),
                  lastDate: DateTime.utc(2026, 9, 21),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      return Future.sync(() => result);
    }

    Future<DateTime?> submit(WidgetTester tester, String digits) async {
      await tester.enterText(find.byKey(const Key('date-input')), digits);
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await tester.pumpAndSettle();
      return null;
    }

    testWidgets('eight digits become a date in the English order', (
      tester,
    ) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDateInputDialog(
                  context: context,
                  initialDate: null,
                  firstDate: DateTime.utc(2020),
                  lastDate: DateTime.utc(2026, 9, 21),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('mm/dd/yyyy'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('date-input')), '09012026');
      expect(find.text('09/01/2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await tester.pumpAndSettle();
      expect(result, DateTime.utc(2026, 9, 1));
    });

    testWidgets('German types day first with dots', (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDateInputDialog(
                  context: context,
                  initialDate: null,
                  firstDate: DateTime.utc(2020),
                  lastDate: DateTime.utc(2026, 9, 21),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('tt.mm.jjjj'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('date-input')), '01092026');
      expect(find.text('01.09.2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('date-input-ok')));
      await tester.pumpAndSettle();
      expect(result, DateTime.utc(2026, 9, 1));
    });

    testWidgets('an impossible or out-of-range date stays in the dialog', (
      tester,
    ) async {
      await open(tester);
      await submit(tester, '13452026');
      expect(find.byKey(const Key('date-input')), findsOneWidget);
      expect(find.text('Invalid format.'), findsOneWidget);

      await submit(tester, '09302026');
      expect(find.text('Out of range.'), findsOneWidget);

      await submit(tester, '09212026');
      expect(find.byKey(const Key('date-input')), findsNothing);
    });

    testWidgets('a known date is prefilled, an unknown one is not', (
      tester,
    ) async {
      await open(tester, initialDate: DateTime.utc(2024, 2, 29));
      final prefilled = tester.widget<TextField>(
        find.byKey(const Key('date-input')),
      );
      expect(prefilled.controller!.text, '02/29/2024');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await open(tester);
      final field = tester.widget<TextField>(
        find.byKey(const Key('date-input')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('the calendar is one tap away and wins', (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDateInputDialog(
                  context: context,
                  initialDate: DateTime.utc(2026, 9, 10),
                  firstDate: DateTime.utc(2020),
                  lastDate: DateTime.utc(2026, 9, 21),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('date-input-calendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(result, DateTime.utc(2026, 9, 15));
      expect(find.byKey(const Key('date-input')), findsNothing);
    });
  });
}
