import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/scenario.dart';
import '../../format/money_format.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/ops_provider.dart';
import '../../providers/repo_providers.dart';
import '../../providers/scenarios_provider.dart';
import '../../providers/write_guard.dart';

/// Creates or edits one scenario: a name plus the accounts and operations it
/// switches off. [scenarioId] `null` means "new".
class ScenarioEditScreen extends ConsumerStatefulWidget {
  final String? scenarioId;

  const ScenarioEditScreen({super.key, this.scenarioId});

  @override
  ConsumerState<ScenarioEditScreen> createState() => _ScenarioEditScreenState();
}

class _ScenarioEditScreenState extends ConsumerState<ScenarioEditScreen> {
  static const _uuid = Uuid();

  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Set<String>? _disabledAccountIds;
  Set<String>? _disabledOpIds;
  bool _saving = false;
  bool _isDefault = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Snapshots the scenario's exclusions into local state once the list has loaded.
  bool _ensureLoaded() {
    if (_disabledAccountIds != null) return true;
    if (widget.scenarioId == null) {
      _disabledAccountIds = <String>{};
      _disabledOpIds = <String>{};
      return true;
    }
    final scenarios = ref.watch(scenariosProvider).valueOrNull;
    if (scenarios == null) return false;
    final existing = scenarios
        .where((s) => s.id == widget.scenarioId)
        .firstOrNull;
    if (existing == null) return false;
    _nameController.text = existing.name;
    _isDefault = existing.isDefault;
    _disabledAccountIds = Set.of(existing.disabledAccountIds);
    _disabledOpIds = Set.of(existing.disabledOpIds);
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = ref.read(currentUserIdProvider) ?? '';
    final scenario = Scenario(
      id: widget.scenarioId ?? _uuid.v4(),
      userId: userId,
      name: _nameController.text.trim(),
      isDefault: _isDefault,
      disabledAccountIds: _disabledAccountIds!,
      disabledOpIds: _disabledOpIds!,
    );

    setState(() => _saving = true);
    final ok = await runWrite(
      context,
      () => ref.read(scenariosProvider.notifier).save(scenario),
      failureMessage: 'Не удалось сохранить сценарий',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ensureLoaded()) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final accounts = ref.watch(activeAccountsProvider);
    final ops = ref.watch(opsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scenarioId == null ? 'Новый сценарий' : 'Сценарий'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Снимите отметку, чтобы исключить из сценария.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Счёта', style: theme.textTheme.titleMedium),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Нет счетов'),
              )
            else
              for (final account in accounts)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !_disabledAccountIds!.contains(account.id),
                  title: Text(account.name),
                  subtitle: Text(
                    formatMoney(account.balance, account.currencyCode),
                  ),
                  onChanged: (included) => setState(() {
                    if (included ?? true) {
                      _disabledAccountIds!.remove(account.id);
                    } else {
                      _disabledAccountIds!.add(account.id);
                    }
                  }),
                ),
            const SizedBox(height: 16),
            Text('Операции', style: theme.textTheme.titleMedium),
            if (ops.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Нет операций'),
              )
            else
              for (final op in ops)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: !_disabledOpIds!.contains(op.id),
                  title: Text(op.title),
                  subtitle: Text(formatMoney(op.amount, op.currencyCode)),
                  onChanged: (included) => setState(() {
                    if (included ?? true) {
                      _disabledOpIds!.remove(op.id);
                    } else {
                      _disabledOpIds!.add(op.id);
                    }
                  }),
                ),
            const SizedBox(height: 24),
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
