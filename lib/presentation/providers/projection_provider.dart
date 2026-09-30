import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/account.dart';
import '../../domain/models/planned_op.dart';
import '../../domain/projection/occurrences.dart';
import '../../domain/projection/project_balance.dart';
import 'accounts_provider.dart';
import 'ops_provider.dart';
import 'rates_provider.dart';
import 'scenarios_provider.dart';
import 'settings_provider.dart';

/// Accounts the active scenario keeps, archived ones already dropped.
final scenarioAccountsProvider = Provider<List<Account>>((ref) {
  final accounts = ref.watch(activeAccountsProvider);
  final scenario = ref.watch(activeScenarioProvider);
  if (scenario == null) return accounts;
  return accounts
      .where((account) => scenario.allowsAccount(account.id))
      .toList();
});

/// Operations the active scenario keeps. The `enabled` flag is left to
/// `projectBalance`, which also has to report it.
final scenarioOpsProvider = Provider<List<PlannedOp>>((ref) {
  final ops = ref.watch(opsProvider).valueOrNull ?? const <PlannedOp>[];
  final scenario = ref.watch(activeScenarioProvider);
  if (scenario == null) return ops;
  return ops.where((op) => scenario.allowsOp(op.id)).toList();
});

/// Today's total in the base currency, with no operations applied yet.
final currentTotalProvider = Provider<ProjectionResult>((ref) {
  final today = dateOnly(DateTime.now());
  return ref.watch(projectionProvider(today));
});

/// The forecast from today up to [date], in the base currency.
///
/// A plain [Provider.family] over the pure `projectBalance`: no async work, no
/// caching subtleties — every input it reads is already in memory.
final projectionProvider = Provider.family<ProjectionResult, DateTime>((
  ref,
  date,
) {
  final from = dateOnly(DateTime.now());
  final to = dateOnly(date);
  return projectBalance(
    accounts: ref.watch(scenarioAccountsProvider),
    ops: ref.watch(scenarioOpsProvider),
    from: from,
    to: to.isBefore(from) ? from : to,
    rates: ref.watch(rateTableProvider),
    baseCurrency: ref.watch(baseCurrencyProvider),
  );
});
