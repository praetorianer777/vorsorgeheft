import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/providers.dart';
import '../domain/person.dart';
import '../l10n/app_localizations.dart';
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
  bool _dateTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? today,
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
    );
    await ref.read(databaseProvider).upsertPerson(person);
    if (mounted) Navigator.of(context).pop();
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
                    child: Text(l10n.dateOfBirth),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.sexLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<Sex>(
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
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save-person'),
              onPressed: _save,
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  String? _dateError(AppLocalizations l10n, DateTime today) {
    if (!_dateTouched) return null;
    if (_dateOfBirth == null) return l10n.dateOfBirthMissing;
    if (_dateOfBirth!.isAfter(today)) return l10n.dateOfBirthInFuture;
    return null;
  }
}
