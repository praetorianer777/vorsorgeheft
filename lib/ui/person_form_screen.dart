import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/providers.dart';
import '../domain/person.dart';
import '../domain/rule.dart';
import '../domain/schedule_engine.dart';
import '../l10n/app_localizations.dart';
import 'date_input.dart';
import 'formatting.dart';

class PersonFormScreen extends ConsumerStatefulWidget {
  const PersonFormScreen({super.key, this.existing});

  final Person? existing;

  @override
  ConsumerState<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends ConsumerState<PersonFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  late DateTime? _dateOfBirth = widget.existing?.dateOfBirth;
  late Sex _sex = widget.existing?.sex ?? Sex.notStated;
  late final Set<String> _optionalRules = {...?widget.existing?.optionalRules};
  bool _dateTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(clockProvider)();
    final picked = await showDateInputDialog(
      context: context,
      initialDate: _dateOfBirth,
      firstDate: DateTime.utc(today.year - 120),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _dateOfBirth = DateTime.utc(picked.year, picked.month, picked.day);
      _dateTouched = true;
    });
  }

  Future<void> _save() async {
    setState(() => _dateTouched = true);
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) return;

    final person = Person(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      dateOfBirth: _dateOfBirth!,
      sex: _sex,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      optionalRules: _optionalRules,
    );
    await ref.read(storeProvider).savePerson(person);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final person = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePersonTitle(person.name)),
        content: Text(l10n.deletePersonBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-person'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(storeProvider).deletePerson(person.id);
    // Back to the family list: the timeline underneath belongs to a person
    // who no longer exists.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? l10n.addPerson : l10n.editPerson),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('person-name'),
              controller: _name,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: l10n.personName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.personNameMissing
                  : null,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.dateOfBirth,
                border: const OutlineInputBorder(),
                errorText: _dateError(l10n, today),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateOfBirth == null
                          ? '—'
                          : formatDate(context, _dateOfBirth!),
                    ),
                  ),
                  TextButton(
                    key: const Key('pick-date-of-birth'),
                    onPressed: _pickDate,
                    child: Text(l10n.pickDate),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.sexLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<Sex>(
              // Three labels plus a check mark do not fit a phone's width, and
              // the selected segment is already filled.
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: Sex.female, label: Text(l10n.sexFemale)),
                ButtonSegment(value: Sex.male, label: Text(l10n.sexMale)),
                ButtonSegment(
                  value: Sex.notStated,
                  label: Text(l10n.sexNotStated),
                ),
              ],
              selected: {_sex},
              onSelectionChanged: (s) => setState(() => _sex = s.first),
            ),
            const SizedBox(height: 8),
            Text(l10n.sexHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.notes,
                border: const OutlineInputBorder(),
              ),
            ),
            ..._optionalVaccinations(context, l10n),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save-person'),
              onPressed: _save,
              child: Text(l10n.save),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                key: const Key('delete-person'),
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.delete),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One switch per optional rule the person could be meant for. A rule for
  /// the other sex is left out rather than shown off, since it could never
  /// apply; with the sex unstated every rule is offered.
  List<Widget> _optionalVaccinations(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final catalogs = ref.watch(catalogsProvider).value;
    if (catalogs == null) return const [];
    final rules = switchableRules(catalogs).where((rule) {
      final sex = rule.eligibility.sex;
      return sex == null || _sex == Sex.notStated || _sex == sex;
    }).toList();
    if (rules.isEmpty) return const [];

    final theme = Theme.of(context);
    return [
      const SizedBox(height: 24),
      Text(l10n.optionalVaccinationsTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(l10n.optionalVaccinationsHelp, style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      for (final rule in rules) _optionalSwitch(context, l10n, rule),
    ];
  }

  Widget _optionalSwitch(
    BuildContext context,
    AppLocalizations l10n,
    Rule rule,
  ) {
    final locale = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    return SwitchListTile(
      key: Key('optional-${rule.id}'),
      contentPadding: EdgeInsets.zero,
      value: _optionalRules.contains(rule.id),
      onChanged: (on) => setState(() {
        on ? _optionalRules.add(rule.id) : _optionalRules.remove(rule.id);
      }),
      title: Text(rule.title(locale)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rule.description(locale)),
          const SizedBox(height: 4),
          Text(
            l10n.sourceLabel(rule.source.name(locale), rule.source.asOf),
            style: theme.textTheme.bodySmall,
          ),
          if (!rule.statutory)
            Text(
              l10n.notStatutory,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      isThreeLine: true,
    );
  }

  String? _dateError(AppLocalizations l10n, DateTime today) {
    if (!_dateTouched) return null;
    if (_dateOfBirth == null) return l10n.dateOfBirthMissing;
    if (_dateOfBirth!.isAfter(today)) return l10n.dateOfBirthInFuture;
    return null;
  }
}
