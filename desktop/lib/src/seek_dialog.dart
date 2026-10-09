import 'package:flutter/material.dart';

/// Returns an absolute target in seconds only after valid confirmation.
/// Cancelling the dialog returns null; the caller owns the playback mutation.
Future<double?> showSeekDialog(
  BuildContext context, {
  required double position,
  required double duration,
}) => showDialog<double>(
  context: context,
  builder: (context) => _SeekDialog(position: position, duration: duration),
);

class _SeekDialog extends StatefulWidget {
  const _SeekDialog({required this.position, required this.duration});
  final double position;
  final double duration;

  @override
  State<_SeekDialog> createState() => _SeekDialogState();
}

class _SeekDialogState extends State<_SeekDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    final duration = widget.duration.isFinite && widget.duration >= 0
        ? widget.duration
        : 0.0;
    final position = widget.position.isFinite
        ? widget.position.clamp(0.0, duration).toDouble()
        : 0.0;
    final text = _clock(position);
    _input = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _parseTime(_input.text));
  }

  String? _validate(String? input) {
    if (!widget.duration.isFinite || widget.duration < 0) {
      return 'The track duration is unavailable.';
    }
    final target = _parseTime(input ?? '');
    if (target == null) {
      return 'Enter a nonnegative time in seconds, mm:ss, or hh:mm:ss.';
    }
    if (target > widget.duration) {
      return 'Time must be at or before ${_clock(widget.duration)}.';
    }
    return null;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Jump to time'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: 'Time',
            hintText: '1:23',
            helperText:
                'Seconds, mm:ss, or hh:mm:ss.\n'
                'Track duration: ${_clock(widget.duration)}',
            helperMaxLines: 2,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Jump')),
    ],
  );
}

// Match the terminal jump parser, including omitted clock components such as
// :49, 58:, and 1::03. Clock seconds/minutes stay below 60; total minutes may
// exceed 59 in the two-component form.
double? _parseTime(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) return null;
  final values = <int>[];
  for (var index = 0; index < parts.length; index++) {
    var part = parts[index].trim();
    if (part.isEmpty && parts.length > 1) part = '0';
    if (!RegExp(r'^\d+$').hasMatch(part)) return null;
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    if (index > 0 && (part.length > 2 || value > 59)) return null;
    values.add(value);
  }
  var target = 0.0;
  for (final value in values) {
    target = target * 60 + value;
  }
  return target.isFinite ? target : null;
}

String _clock(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final total = seconds.floor();
  final hours = total ~/ 3600;
  final minutes = total ~/ 60;
  final tail = (total % 60).toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$tail';
  return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$tail';
}
