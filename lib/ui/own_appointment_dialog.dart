import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/own_appointment.dart';
import '../l10n/app_localizations.dart';
import 'date_input.dart';
import 'formatting.dart';

/// Collects an own appointment: what it is, when it is first, how often it
/// repeats. Returns null when cancelled; the caller decides when to store it.
Future<OwnAppointment?> showOwnAppointmentDialog({
  required BuildContext context,
  required String personId,
  required DateTime today,
  OwnAppointment? existing,
}) => showDialog<OwnAppointment>(
  context: context,
  builder: (context) => _OwnAppointmentDialog(
    personId: personId,
    today: today,
    existing: existing,
  ),
);

/// "Every 24 months" reads as "every 2 years"; the stored value is months.
String repeatLabel(AppLocalizations l10n, int everyMonths) =>
    everyMonths % 12 == 0
    ? l10n.ownRepeatYears(everyMonths ~/ 12)
    : l10n.ownRepeatMonths(everyMonths);

enum _Unit { months, years }

class _OwnAppointmentDialog extends StatefulWidget {
  const _OwnAppointmentDialog({
    required this.personId,
    required this.today,
    this.existing,
  });

  final String personId;
  final DateTime today;
  final OwnAppointment? existing;

  @override
  State<_OwnAppointmentDialog> createState() => _OwnAppointmentDialogState();
}

class _OwnAppointmentDialogState extends State<_OwnAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  late final TextEditingController _every = TextEditingController(
    text: _initialEvery().toString(),
  );
  late _Unit _unit = _initialUnit();
  late DateTime? _firstOn = widget.existing?.firstOn;
  bool _firstTouched = false;

  _Unit _initialUnit() {
    final months = widget.existing?.everyMonths ?? 12;
    return months % 12 == 0 ? _Unit.years : _Unit.months;
  }

  int _initialEvery() {
    final months = widget.existing?.everyMonths ?? 12;
    return months % 12 == 0 ? months ~/ 12 : months;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _every.dispose();
    super.dispose();
  }

  Future<void> _pickFirst() async {
    final picked = await showDateInputDialog(
      context: context,
      initialDate: _firstOn,
      firstDate: DateTime.utc(widget.today.year - 50),
      lastDate: DateTime.utc(widget.today.year + 50),
    );
    if (picked == null) return;
    setState(() {
      _firstOn = picked;
      _firstTouched = true;
    });
  }

  void _submit() {
    setState(() => _firstTouched = true);
    if (!_formKey.currentState!.validate() || _firstOn == null) return;
    final count = int.parse(_every.text.trim());
    final note = _note.text.trim();
    Navigator.of(context).pop(
      OwnAppointment(
        id: widget.existing?.id ?? const Uuid().v4(),
        personId: widget.personId,
        title: _title.text.trim(),
        firstOn: _firstOn!,
        everyMonths: _unit == _Unit.years ? count * 12 : count,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l10n.addOwnAppointment
            : l10n.editOwnAppointment,
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('own-title'),
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.ownAppointmentTitle,
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.ownAppointmentTitleMissing
                    : null,
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.ownAppointmentFirstOn,
                  errorText: _firstTouched && _firstOn == null
                      ? l10n.ownAppointmentFirstOnMissing
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _firstOn == null ? '—' : formatDate(context, _firstOn!),
                      ),
                    ),
                    TextButton(
                      key: const Key('own-first-on'),
                      onPressed: _pickFirst,
                      child: Text(l10n.pickDate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      key: const Key('own-every'),
                      controller: _every,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.ownAppointmentEvery,
                      ),
                      validator: (value) =>
                          (int.tryParse(value ?? '') ?? 0) < 1 ? '' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SegmentedButton<_Unit>(
                        key: const Key('own-unit'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _Unit.months,
                            label: Text(l10n.unitMonths),
                          ),
                          ButtonSegment(
                            value: _Unit.years,
                            label: Text(l10n.unitYears),
                          ),
                        ],
                        selected: {_unit},
                        onSelectionChanged: (s) =>
                            setState(() => _unit = s.first),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('own-note'),
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.ownAppointmentNote),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('own-save'),
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
