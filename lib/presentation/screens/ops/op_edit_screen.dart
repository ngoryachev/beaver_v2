import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/currency.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/planned_op.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/ops_provider.dart';
import '../../providers/write_guard.dart';
import 'op_labels.dart';

/// Creates or edits one planned operation. [opId] `null` means "new".
class OpEditScreen extends ConsumerStatefulWidget {
  final String? opId;

  const OpEditScreen({super.key, this.opId});

  @override
  ConsumerState<OpEditScreen> createState() => _OpEditScreenState();
}

class _OpEditScreenState extends ConsumerState<OpEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  PlannedOp? _draft;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Loads the operation being edited once the list is available, or starts a new
  /// one. Kept out of `initState` because the ops list may still be loading then.
  PlannedOp? _ensureDraft() {
    if (_draft != null) return _draft;

    if (widget.opId == null) {
      _draft = ref.read(opsProvider.notifier).draft();
      return _draft;
    }
    final ops = ref.watch(opsProvider).valueOrNull;
    if (ops == null) return null;
    final existing = ops.where((op) => op.id == widget.opId).firstOrNull;
    if (existing == null) return null;
    _draft = existing;
    _titleController.text = existing.title;
    _amountController.text = moneyToInput(
      existing.amount,
      existing.currencyCode,
    );
    return _draft;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final draft = _draft!;
    final initial = isStart
        ? draft.startDate
        : (draft.endDate ?? draft.startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // The end date can never precede the start: the database enforces
      // `end_date >= start_date`, and a rejected write would surface only as a
      // generic «Не удалось сохранить операцию».
      firstDate: isStart ? DateTime(2000) : draft.startDate,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final date = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _draft = isStart
          ? draft.copyWith(
              startDate: date,
              // Keeping an end date before the new start would violate the
              // `end_date >= start_date` check, so it is dropped.
              clearEndDate:
                  draft.endDate != null && draft.endDate!.isBefore(date),
            )
          : draft.copyWith(endDate: date);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = _draft!;
    final decimals = Currency.decimalsOf(draft.currencyCode);
    final amount = Money.tryParse(_amountController.text, decimals: decimals);
    if (amount == null || amount.minor <= 0) return;

    // An account id that resolves to nothing would be rejected by the foreign
    // key; the editor already shows «Любой» for it, so save that.
    final allAccounts = ref.read(accountsProvider).valueOrNull ?? const [];
    final dangling =
        draft.accountId != null &&
        !allAccounts.any((account) => account.id == draft.accountId);

    setState(() => _saving = true);
    final ok = await runWrite(
      context,
      () => ref
          .read(opsProvider.notifier)
          .save(
            draft.copyWith(
              title: _titleController.text.trim(),
              amount: amount.minor,
              currencyCode: Currency.byCode(draft.currencyCode).code,
              clearAccountId: dangling,
            ),
          ),
      failureMessage: 'Не удалось сохранить операцию',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _ensureDraft();
    if (draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final activeAccounts = ref.watch(activeAccountsProvider);
    final allAccounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    // A dropdown asserts unless its value is among its items, so both lists
    // below have to admit whatever the operation already stores.

    // The account may have been archived since; keep it listed (marked) rather
    // than dropping it — silently re-pointing the operation at «Любой» would
    // lose what the user meant. An id matching nothing at all (the FK nulls it
    // on delete, so only a hand-edited row) falls back to «Любой».
    final referenced = draft.accountId == null
        ? null
        : allAccounts.where((a) => a.id == draft.accountId).firstOrNull;
    final accounts = <Account>[
      ...activeAccounts,
      if (referenced != null && referenced.archived) referenced,
    ];
    final selectedAccountId = accounts.any((a) => a.id == draft.accountId)
        ? draft.accountId
        : null;

    // `Currency.byCode` tolerates a code this build does not know — one written
    // by a newer build, or straight into a column whose CHECK is only
    // `^[A-Z]{3}$` — so the editor must tolerate it too. The shown value comes
    // from the same lookup as the item, because `byCode` also canonicalises the
    // case: resolving the two separately would mismatch on a stored `pln`.
    final currency = Currency.byCode(draft.currencyCode);
    final currencies = <Currency>[
      ...Currency.all,
      if (!Currency.all.contains(currency)) currency,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.opId == null ? 'Новая операция' : 'Операция'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<OpKind>(
              segments: [
                for (final kind in OpKind.values)
                  ButtonSegment(value: kind, label: Text(kindLabel(kind))),
              ],
              selected: {draft.kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(
                () => _draft = draft.copyWith(kind: selection.first),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Сумма',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = Money.tryParse(
                        value ?? '',
                        decimals: Currency.decimalsOf(draft.currencyCode),
                      );
                      if (parsed == null) return 'Введите сумму';
                      if (parsed.minor <= 0) return 'Сумма больше нуля';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: currency.code,
                    decoration: const InputDecoration(
                      labelText: 'Валюта',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final currency in currencies)
                        DropdownMenuItem(
                          value: currency.code,
                          child: Text(currency.code),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () =>
                          _draft = draft.copyWith(currencyCode: value ?? 'RUB'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<OpCategory>(
              initialValue: draft.category,
              decoration: const InputDecoration(
                labelText: 'Категория',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in OpCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Row(
                      children: [
                        Icon(categoryIcon(category), size: 18),
                        const SizedBox(width: 8),
                        Text(categoryLabel(category)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(
                () => _draft = draft.copyWith(
                  category: value ?? OpCategory.other,
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Schedule>(
              initialValue: draft.schedule,
              decoration: const InputDecoration(
                labelText: 'Повтор',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final schedule in Schedule.values)
                  DropdownMenuItem(
                    value: schedule,
                    child: Text(scheduleLabel(schedule)),
                  ),
              ],
              onChanged: (value) => setState(
                () => _draft = draft.copyWith(
                  schedule: value ?? Schedule.monthly,
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: selectedAccountId,
              decoration: const InputDecoration(
                labelText: 'Счёт',
                helperText: 'Не обязательно: влияет только на общий итог',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Любой')),
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      account.archived
                          ? '${account.name} (в архиве)'
                          : account.name,
                    ),
                  ),
              ],
              onChanged: (value) => setState(
                () => _draft = value == null
                    ? draft.copyWith(clearAccountId: true)
                    : draft.copyWith(accountId: value),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(draft.schedule == Schedule.once ? 'Дата' : 'Начало'),
              subtitle: Text(formatDate(draft.startDate)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _pickDate(isStart: true),
            ),
            // A one-off operation has a single date; an end date would be noise.
            if (draft.schedule != Schedule.once)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy),
                title: const Text('Окончание'),
                subtitle: Text(
                  draft.endDate == null
                      ? 'Без ограничения'
                      : formatDate(draft.endDate!),
                ),
                trailing: draft.endDate == null
                    ? const Icon(Icons.edit_calendar_outlined)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Убрать окончание',
                        onPressed: () => setState(
                          () => _draft = draft.copyWith(clearEndDate: true),
                        ),
                      ),
                onTap: () => _pickDate(isStart: false),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.enabled,
              title: const Text('Учитывать в прогнозе'),
              onChanged: (enabled) =>
                  setState(() => _draft = draft.copyWith(enabled: enabled)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
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
      ),
    );
  }
}
