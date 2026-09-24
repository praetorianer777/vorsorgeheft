import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vorsorgeheft/domain/person.dart';

import '../../integration_test/fixtures/family.dart';
import '../../integration_test/helpers/app_harness.dart';
import '../support/synchronous_assets.dart';

/// Renders the pictures the Play Store listing needs.
///
/// They are generated rather than taken by hand so they cannot show an older
/// version of the app than the one being released. tools/store-graphics.sh
/// points STORE_GRAPHICS_DIR at docs/store and commits the result; an
/// ordinary test run writes into build/ and only checks that the generator
/// still works.
void main() {
  specAssetBundle = SynchronousAssetBundle();

  final directory = Directory(
    Platform.environment['STORE_GRAPHICS_DIR'] ?? 'build/store',
  )..createSync(recursive: true);

  setUpAll(() async {
    await _loadRealFonts();
    // The banner belongs to a debug build; the store listing shows what a
    // release build looks like.
    WidgetsApp.debugAllowBannerOverride = false;
  });

  final dog = Person(
    id: 'dog',
    name: 'Bello',
    dateOfBirth: DateTime.utc(2025, 7, 20),
    species: Species.dog,
  );

  for (final locale in [const Locale('de'), const Locale('en')]) {
    final tag = locale.languageCode;

    testWidgets('the phone screenshots in $tag', (tester) async {
      _phone(tester);
      await _realShadows(() async {
        final db = await launchApp(
          tester,
          people: [...Family.all, dog],
          locale: locale,
        );

        await _shoot(tester, directory, '$tag-1-family');

        await tester.tap(find.text('Mila'));
        await settle(tester);
        await _shoot(tester, directory, '$tag-2-timeline');

        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w.key is ValueKey<String> && _isOccurrence(w.key!),
              )
              .first,
        );
        await settle(tester);
        await _shoot(tester, directory, '$tag-3-appointment');

        await _back(tester);
        await _back(tester);
        await tester.tap(find.byKey(const Key('open-settings')));
        await settle(tester);
        await scrollTo(tester, find.byKey(const Key('open-sources')));
        await tester.ensureVisible(find.byKey(const Key('open-sources')));
        await tester.tap(find.byKey(const Key('open-sources')));
        await settle(tester);
        await _shoot(tester, directory, '$tag-4-sources');

        await shutDown(tester, db);
      });
    });

    testWidgets('the feature graphic in $tag', (tester) async {
      tester.view.physicalSize = const Size(1024, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final icon = await tester.runAsync(
        () => _decode(File('assets/icon/icon.png')),
      );
      await _realShadows(() async {
        await tester.pumpWidget(_FeatureGraphic(locale: locale, icon: icon!));
        await settle(tester);
        await _shoot(tester, directory, '$tag-feature-graphic');
      });
    });
  }

  testWidgets('the store icon', (tester) async {
    tester.view.physicalSize = const Size(512, 512);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final icon = await tester.runAsync(
      () => _decode(File('assets/icon/icon.png')),
    );
    // On the square canvas the rounded corners of the launcher icon fill with
    // its own background colour: the store rounds the tile itself, and a
    // second rounding on top of the first looks like a mistake.
    await tester.pumpWidget(
      ColoredBox(
        color: _seed,
        child: RawImage(image: icon!, width: 512, height: 512),
      ),
    );
    await settle(tester);
    await _shoot(tester, directory, 'icon-512');
  });

  test('every picture is there and has the size the store demands', () {
    final expected = {
      'icon-512.png': const Size(512, 512),
      for (final tag in ['de', 'en']) ...{
        '$tag-1-family.png': const Size(1080, 1920),
        '$tag-2-timeline.png': const Size(1080, 1920),
        '$tag-3-appointment.png': const Size(1080, 1920),
        '$tag-4-sources.png': const Size(1080, 1920),
        '$tag-feature-graphic.png': const Size(1024, 500),
      },
    };

    for (final entry in expected.entries) {
      final file = File(p.join(directory.path, entry.key));
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(_pngSize(file), entry.value, reason: entry.key);
      // A screen that failed to render is a single flat colour, and the file
      // size is what gives that away before anyone looks at it.
      expect(file.lengthSync(), greaterThan(10000), reason: entry.key);
    }
  });
}

/// Reads the width and height out of the PNG header, which is a fixed
/// offset into the file and needs no image decoder.
Size _pngSize(File file) {
  final header = file.readAsBytesSync().sublist(16, 24).buffer.asByteData();
  return Size(header.getUint32(0).toDouble(), header.getUint32(4).toDouble());
}

/// Not pageBack: it looks for a back button by its English tooltip, and half
/// of these screenshots are taken in German.
Future<void> _back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await settle(tester);
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

bool _isOccurrence(Key key) =>
    key is ValueKey<String> && key.value.startsWith('occurrence-');

/// Tests paint a shadow as a hard black outline, which on a screenshot looks
/// like a rendering fault around every raised button and card.
///
/// The binding insists the flag is back where it found it by the time the
/// body returns - before any teardown runs - so it is restored here.
Future<void> _realShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// A 1080x1920 portrait phone, the shape the store asks for.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shoot(
  WidgetTester tester,
  Directory directory,
  String name,
) async {
  final view = tester.binding.renderViews.single;
  final layer = view.debugLayer! as OffsetLayer;
  // Encoding a layer is real asynchronous work on the engine, and the test
  // clock never advances far enough for it on its own; outside runAsync it
  // hangs and leaves the next tap with a guarded-function conflict.
  final bytes = await tester.runAsync(() async {
    final image = await layer.toImage(view.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File(p.join(directory.path, '$name.png')).writeAsBytesSync(bytes!);
}

/// Without this the test renderer draws every glyph as a box.
///
/// The fonts come out of the Flutter SDK the run is using, which is where the
/// engine takes them from on a real Android device as well.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  expect(root, isNotNull, reason: 'FLUTTER_ROOT is set by `flutter test`');
  final fonts = Directory(
    p.join(root!, 'bin', 'cache', 'artifacts', 'material_fonts'),
  );

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File(p.join(fonts.path, file)).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _seed = Color(0xFF2E7D6F);

class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.locale, required this.icon});

  final Locale locale;

  /// Decoded ahead of the frame: an Image widget would still be loading when
  /// the picture is taken.
  final ui.Image icon;

  @override
  Widget build(BuildContext context) {
    final german = locale.languageCode == 'de';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Without a Material ancestor the framework paints text in its
      // missing-style warning: bold with a yellow underline.
      home: Material(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_seed, Color(0xFF1B4F47)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Row(
              children: [
                RawImage(image: icon, width: 220, height: 220),
                const SizedBox(width: 48),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vorsorgeheft',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        german
                            ? 'Alle Vorsorgetermine der Familie, rechtzeitig\nerinnert. Ohne Konto, ohne Server.'
                            : 'Check-ups and vaccinations for the whole family,\nremembered in time. No account, no server.',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
