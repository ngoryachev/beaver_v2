import 'package:flutter/material.dart';

/// How a typed number is applied to the current balance.
enum KeypadMode {
  /// Replace the balance with the typed number.
  set('='),

  /// Add the typed number to the balance.
  add('+'),

  /// Subtract the typed number from the balance.
  subtract('−');

  final String label;
  const KeypadMode(this.label);
}

/// On-screen numeric keypad.
///
/// The app ships its own instead of relying on the OS keyboard: the balance
/// editor needs the `=`/`+`/`−` mode switch right next to the digits, and on web
/// there is no numeric keyboard at all.
class AmountKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final KeypadMode? mode;
  final ValueChanged<KeypadMode>? onModeChanged;

  /// Decimal separator; hidden for zero-decimal currencies such as JPY.
  final bool allowDecimal;

  const AmountKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.mode,
    this.onModeChanged,
    this.allowDecimal = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (mode != null && onModeChanged != null) ...[
          SegmentedButton<KeypadMode>(
            segments: [
              for (final value in KeypadMode.values)
                ButtonSegment(
                  value: value,
                  label: Text(
                    value.label,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
            ],
            selected: {mode!},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onModeChanged!(selection.first),
          ),
          const SizedBox(height: 12),
        ],
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          _row(row.map((digit) => _key(context, digit, () => onDigit(digit)))),
        _row([
          allowDecimal
              ? _key(context, ',', () => onDigit(','))
              : const Expanded(child: SizedBox.shrink()),
          _key(context, '0', () => onDigit('0')),
          _key(
            context,
            null,
            onBackspace,
            icon: Icons.backspace_outlined,
            semanticLabel: 'Стереть',
          ),
        ]),
      ],
    );
  }

  Widget _row(Iterable<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: children.toList()),
  );

  Widget _key(
    BuildContext context,
    String? label,
    VoidCallback onPressed, {
    IconData? icon,
    String? semanticLabel,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: onPressed,
            child: icon != null
                ? Icon(icon, semanticLabel: semanticLabel)
                : Text(label!, style: const TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
  }
}
