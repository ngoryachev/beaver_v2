import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/currency.dart';
import '../../../domain/models/money.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/write_guard.dart';
import 'widgets/amount_keypad.dart';

/// Edits one account's balance.
///
/// Three modes, because that is how the balance is actually corrected in
/// practice: «=» types the new balance outright, «+» and «−» adjust the current
/// one — no mental arithmetic needed to record «spent 250».
class BalanceEditSheet extends ConsumerStatefulWidget {
  final Account account;

  const BalanceEditSheet({super.key, required this.account});

  static Future<void> show(BuildContext context, Account account) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BalanceEditSheet(account: account),
    );
  }

  @override
  ConsumerState<BalanceEditSheet> createState() => _BalanceEditSheetState();
}

class _BalanceEditSheetState extends ConsumerState<BalanceEditSheet> {
  KeypadMode _mode = KeypadMode.set;
  String _input = '';
  bool _saving = false;

  Account get _account => widget.account;

  int get _decimals => Currency.decimalsOf(_account.currencyCode);

  /// The typed number in minor units, or `null` when nothing usable was typed.
  int? get _typedMinor => _input.isEmpty
      ? null
      : Money.tryParse(_input, decimals: _decimals)?.minor;

  /// Balance the account would end up with.
  int get _resultBalance {
    final typed = _typedMinor;
    if (typed == null) return _account.balance;
    return switch (_mode) {
      KeypadMode.set => typed,
      KeypadMode.add => _account.balance + typed,
      KeypadMode.subtract => _account.balance - typed,
    };
  }

  void _digit(String digit) {
    setState(() {
      if (digit == ',') {
        if (_input.contains(',')) return;
        _input = _input.isEmpty ? '0,' : '$_input,';
        return;
      }
      // Cap the fractional part at the currency's precision, so typing does not
      // silently produce a value that gets rounded on save.
      final separator = _input.indexOf(',');
      if (separator >= 0 && _input.length - separator - 1 >= _decimals) return;
      if (_input == '0') {
        _input = digit;
        return;
      }
      _input += digit;
    });
  }

  void _backspace() {
    setState(() {
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  Future<void> _save() async {
    if (_typedMinor == null) return;
    setState(() => _saving = true);
    final target = _resultBalance;
    final ok = await runWrite(
      context,
      () => ref.read(accountsProvider.notifier).setBalance(_account, target),
      failureMessage: 'Не удалось изменить баланс',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _typedMinor;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_account.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Сейчас ${formatMoney(_account.balance, _account.currencyCode)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(_mode.label, style: theme.textTheme.headlineSmall),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _input.isEmpty ? '0' : _input,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Currency.byCode(_account.currencyCode).symbol,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            typed == null
                ? 'Введите сумму'
                : 'Станет ${formatMoney(_resultBalance, _account.currencyCode)}',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          AmountKeypad(
            onDigit: _digit,
            onBackspace: _backspace,
            mode: _mode,
            onModeChanged: (mode) => setState(() => _mode = mode),
            allowDecimal: _decimals > 0,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: typed == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
