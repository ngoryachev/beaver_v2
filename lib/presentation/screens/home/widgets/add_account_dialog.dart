import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/currency.dart';
import '../../../../domain/models/money.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/write_guard.dart';

/// Creates an account: a name, a currency and an optional starting balance.
class AddAccountDialog extends ConsumerStatefulWidget {
  const AddAccountDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const AddAccountDialog(),
    );
  }

  @override
  ConsumerState<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  String _currencyCode = Currency.rub.code;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final decimals = Currency.decimalsOf(_currencyCode);
    final balance = _balanceController.text.trim().isEmpty
        ? 0
        : Money.tryParse(_balanceController.text, decimals: decimals)?.minor ??
              0;

    setState(() => _saving = true);
    final ok = await runWrite(
      context,
      () => ref
          .read(accountsProvider.notifier)
          .add(
            name: _nameController.text,
            currencyCode: _currencyCode,
            balance: balance,
          ),
      failureMessage: 'Не удалось создать счёт',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый счёт'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currencyCode,
              decoration: const InputDecoration(
                labelText: 'Валюта',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final currency in Currency.all)
                  DropdownMenuItem(
                    value: currency.code,
                    child: Text('${currency.code} ${currency.symbol}'),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _currencyCode = value ?? Currency.rub.code),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Баланс',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
