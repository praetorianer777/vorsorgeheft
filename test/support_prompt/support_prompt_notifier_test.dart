import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/app/providers.dart';
import 'package:vorsorgeheft/data/database.dart';
import 'package:vorsorgeheft/data/database_provider.dart';
import 'package:vorsorgeheft/domain/completion.dart';
import 'package:vorsorgeheft/domain/person.dart';
import 'package:vorsorgeheft/support/support_prompt.dart';
import 'package:vorsorgeheft/support/support_prompt_notifier.dart';
import 'package:vorsorgeheft/sync/replicated_store.dart';

void main() {
  late AppDatabase database;
  late ReplicatedStore store;

  setUp(() async {
    database = openInMemoryDatabase();
    store = await ReplicatedStore.open(
      database,
      nodeId: 'test',
      clock: () => DateTime.utc(2026, 9, 20),
    );
    await store.savePerson(
      Person(id: 'p', name: 'Mila', dateOfBirth: DateTime.utc(2026, 9, 1)),
    );
  });
  tearDown(() => database.close());

  /// Both the dismissed flag and the completions arrive asynchronously, so
  /// the provider is polled until it settles, as a rebuilt widget would.
  Future<bool> due(ProviderContainer container) async {
    container.listen(completionsProvider, (_, _) {});
    container.listen(supportPromptDismissedProvider, (_, _) {});
    var value = false;
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
      value = container.read(supportPromptDueProvider);
    }
    return value;
  }

  ProviderContainer restart() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        storeProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> record(String ruleId, {bool skipped = false}) =>
      store.recordCompletion(
        Completion(
          personId: 'p',
          ruleId: ruleId,
          completedOn: DateTime.utc(2026, 9, 20),
          skipped: skipped,
        ),
      );

  test('not due on a first launch, due at the third recorded', () async {
    expect(await due(restart()), isFalse);

    await record('u1');
    await record('u2');
    expect(await due(restart()), isFalse);

    await record('u3');
    expect(await due(restart()), isTrue);
  });

  test(
    'a skip is a decision, not an appointment the app reminded of',
    () async {
      await record('u1');
      await record('u2');
      await record('u3', skipped: true);
      expect(await due(restart()), isFalse);
    },
  );

  test('dismissing it once keeps it away across restarts', () async {
    for (final rule in ['u1', 'u2', 'u3']) {
      await record(rule);
    }
    final first = restart();
    expect(await due(first), isTrue);

    await first.read(supportPromptDismissedProvider.notifier).dismiss();
    expect(await due(first), isFalse);

    expect(await database.settingValue(supportPromptDismissedKey), 'true');
    expect(await due(restart()), isFalse);
  });

  test('the flag stays on this device', () async {
    final container = restart();
    await container.read(supportPromptDismissedProvider.notifier).dismiss();

    expect(
      await database.changesFor('setting', supportPromptDismissedKey),
      isEmpty,
    );
  });
}
