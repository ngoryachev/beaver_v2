import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/currency.dart';
import '../../../domain/models/money.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/rates_provider.dart';
import '../../providers/write_guard.dart';

/// Moves money between two accounts.
///
/// A cross-currency transfer carries two amounts: what leaves the source and what
/// lands in the destination. The credited side is prefilled from the stored rate
/// but stays editable, because the bank's actual rate is never exactly the stored
/// one and the balances have to match reality.
class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const TransferSheet(),
    );
  }

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  String? _fromId;
  String? _toId;

  /// `true` once the user edits the credited amount by hand; from then on the
  /// rate no longer overwrites it. Reset whenever either account changes — the
  /// correction applied to the old pair, not the new one.
  bool _toEditedManually = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromController.addListener(_syncToAmount);
  }

  @override
  void dispose() {
    _fromController.removeListener(_syncToAmount);
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  List<Account> get _accounts => ref.read(activeAccountsProvider);

  Account? _accountById(String? id) =>
      id == null ? null : _accounts.where((a) => a.id == id).firstOrNull;

  bool get _sameCurrency {
    final from = _accountById(_fromId);
    final to = _accountById(_toId);
    if (from == null || to == null) return true;
    return from.currencyCode.toUpperCase() == to.currencyCode.toUpperCase();
  }

  /// Picks one side of the transfer. Any hand-entered credited amount belonged
  /// to the previous pair of accounts, so it is discarded and recomputed.
  void _selectAccount(String? accountId, {required bool isSource}) {
    setState(() {
      if (isSource) {
        _fromId = accountId;
      } else {
        _toId = accountId;
      }
      _toEditedManually = false;
      _syncToAmount();
    });
  }

  /// Recomputes the credited amount from the debited one, unless the user has
  /// taken it over.
  void _syncToAmount() {
    if (_toEditedManually) return;
    final from = _accountById(_fromId);
    final to = _accountById(_toId);
    if (from == null || to == null) return;

    final debited = Money.tryParse(
      _fromController.text,
      decimals: Currency.decimalsOf(from.currencyCode),
    );
    if (debited == null) {
      _toController.text = '';
      return;
    }
    if (_sameCurrency) {
      _toController.text = moneyToInput(debited.minor, to.currencyCode);
      return;
    }
    final converted = ref
        .read(rateTableProvider)
        .convertMinor(
          debited.minor,
          from: from.currencyCode,
          to: to.currencyCode,
        );
    _toController.text = converted == null
        ? ''
        : moneyToInput(converted, to.currencyCode);
  }

  Future<void> _submit() async {
    final from = _accountById(_fromId);
    final to = _accountById(_toId);
    if (from == null || to == null) {
      setState(() => _error = 'Выберите оба счёта');
      return;
    }
    if (from.id == to.id) {
      setState(() => _error = 'Счёта должны быть разными');
      return;
    }
    final debited = Money.tryParse(
      _fromController.text,
      decimals: Currency.decimalsOf(from.currencyCode),
    );
    if (debited == null || debited.minor <= 0) {
      setState(() => _error = 'Введите сумму списания');
      return;
    }
    // With one currency the credited amount is the debited one by definition —
    // the field is hidden, so its contents must never reach the transfer.
    final credited = _sameCurrency
        ? debited
        : Money.tryParse(
            _toController.text,
            decimals: Currency.decimalsOf(to.currencyCode),
          );
    if (credited == null || credited.minor <= 0) {
      setState(() => _error = 'Введите сумму зачисления');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    final ok = await runWrite(
      context,
      () => ref
          .read(accountsProvider.notifier)
          .transfer(
            fromAccountId: from.id,
            toAccountId: to.id,
            fromAmount: debited.minor,
            toAmount: credited.minor,
          ),
      failureMessage: 'Не удалось выполнить перевод',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(activeAccountsProvider);
    final from = _accountById(_fromId);
    final to = _accountById(_toId);

    if (accounts.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Для перевода нужно хотя бы два счёта',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Перевод', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _fromId,
              decoration: const InputDecoration(
                labelText: 'Откуда',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · '
                      '${formatMoney(account.balance, account.currencyCode)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => _selectAccount(value, isSource: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _toId,
              decoration: const InputDecoration(
                labelText: 'Куда',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · '
                      '${formatMoney(account.balance, account.currencyCode)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => _selectAccount(value, isSource: false),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fromController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Списать',
                border: const OutlineInputBorder(),
                suffixText: from == null
                    ? null
                    : Currency.byCode(from.currencyCode).symbol,
              ),
            ),
            // With one currency the credited amount always equals the debited one,
            // so a second field would only be a way to get it wrong.
            if (!_sameCurrency) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _toController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _toEditedManually = true,
                decoration: InputDecoration(
                  labelText: 'Зачислить',
                  helperText: 'По курсу, можно поправить',
                  border: const OutlineInputBorder(),
                  suffixText: to == null
                      ? null
                      : Currency.byCode(to.currencyCode).symbol,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Перевести'),
            ),
          ],
        ),
      ),
    );
  }
}
