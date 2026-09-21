import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Keeps a date field to its digits and puts the separators in by itself, so
/// a date is typed as eight digits on the number pad. The order of day, month
/// and year is the locale's; only the separator is this formatter's business.
class DateSeparatorFormatter extends TextInputFormatter {
  const DateSeparatorFormatter(this.separator);

  final String separator;

  static final _notDigit = RegExp(r'\D');

  String format(String digits) {
    final d = digits.replaceAll(_notDigit, '');
    final buffer = StringBuffer();
    for (var i = 0; i < d.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write(separator);
      buffer.write(d[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(_notDigit, '');
    // Backspace over a separator removes only the separator, which the
    // reformat would put straight back; taking the digit before it with it
    // is what the person meant.
    final deleting = newValue.text.length < oldValue.text.length;
    if (deleting && digits.isNotEmpty && format(digits) == oldValue.text) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = format(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The separator the locale writes between day, month and year, read off the
/// hint Material shows for the same field ("dd.mm.yyyy", "mm/dd/yyyy").
String dateSeparatorOf(MaterialLocalizations localizations) {
  final match = RegExp(r'[^\w]').firstMatch(localizations.dateHelpText);
  return match?.group(0) ?? '.';
}

/// The date as the field shows it once typed: Material's compact form drops
/// the leading zeros ("2/9/2024"), which the formatter would read as a
/// different date, so every part is padded back to two digits.
String prefilledDate(MaterialLocalizations localizations, DateTime date) {
  final separator = dateSeparatorOf(localizations);
  return localizations
      .formatCompactDate(date)
      .split(RegExp(r'\D+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part.length == 1 ? '0$part' : part)
      .join(separator);
}

/// A date dialog whose first offer is the keyboard: a number-pad field that
/// completes its own separators, with the calendar one tap away. [initialDate]
/// prefills the field; null leaves it empty for a date not yet known.
Future<DateTime?> showDateInputDialog({
  required BuildContext context,
  required DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) => _DateInputDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  ),
);

class _DateInputDialog extends StatefulWidget {
  const _DateInputDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateInputDialog> createState() => _DateInputDialogState();
}

class _DateInputDialogState extends State<_DateInputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initialDate;
    if (_controller.text.isEmpty && initial != null) {
      _controller.text = prefilledDate(
        MaterialLocalizations.of(context),
        initial,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);

  void _submit() {
    final localizations = MaterialLocalizations.of(context);
    final parsed = localizations.parseCompactDate(_controller.text);
    if (parsed == null) {
      setState(() => _error = localizations.invalidDateFormatLabel);
      return;
    }
    final day = _day(parsed);
    if (day.isBefore(_day(widget.firstDate)) ||
        day.isAfter(_day(widget.lastDate))) {
      setState(() => _error = localizations.dateOutOfRangeLabel);
      return;
    }
    Navigator.of(context).pop(day);
  }

  Future<void> _openCalendar() async {
    final localizations = MaterialLocalizations.of(context);
    final typed = localizations.parseCompactDate(_controller.text);
    final navigator = Navigator.of(context);
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDate: typed ?? widget.initialDate ?? widget.lastDate,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
    );
    if (picked == null || !mounted) return;
    navigator.pop(_day(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.pickDate),
      content: TextField(
        key: const Key('date-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          DateSeparatorFormatter(dateSeparatorOf(localizations)),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: localizations.dateHelpText,
          errorText: _error,
          suffixIcon: IconButton(
            key: const Key('date-input-calendar'),
            icon: const Icon(Icons.calendar_month),
            tooltip: localizations.calendarModeButtonLabel,
            onPressed: _openCalendar,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancelButtonLabel),
        ),
        TextButton(
          key: const Key('date-input-ok'),
          onPressed: _submit,
          child: Text(localizations.okButtonLabel),
        ),
      ],
    );
  }
}
