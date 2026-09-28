import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/rate.dart';
import 'accounts_provider.dart';
import 'ops_provider.dart';
import 'rates_provider.dart';
import 'repo_providers.dart';

/// Rates older than this are refetched on the next opportunity.
const rateStalenessThreshold = Duration(hours: 24);

/// Minimum gap between two resume-triggered checks. Android and the browser can
/// fire several resume events in a row; without this the app would hammer the
/// rate API while the user flips between windows.
const _resumeThrottle = Duration(seconds: 2);

/// Keeps the stored rates reasonably fresh.
///
/// Refreshes when the app starts and when it returns to the foreground, if the
/// freshest `auto` row is older than [rateStalenessThreshold] or some currency in
/// use has no rate at all. Manual rates are never touched — see
/// [RatesNotifier.applyAuto].
class RateRefreshController extends Notifier<AsyncValue<void>> {
  DateTime? _lastCheck;
  bool _running = false;

  /// Codes the last successful fetch came back without. Neither source knows
  /// them, so treating them as "missing a rate" would make every resume fire a
  /// fresh request for ever; they wait for the normal staleness window instead.
  final Set<String> _unfetchable = {};

  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Refreshes if the rates are stale. Called on start-up and on resume.
  Future<void> refreshIfStale() async {
    final now = DateTime.now();
    final lastCheck = _lastCheck;
    if (lastCheck != null && now.difference(lastCheck) < _resumeThrottle) {
      return;
    }
    _lastCheck = now;

    if (!await _awaitData()) return;

    // A currency with no row at all beats the staleness window: adding a EUR
    // account should not leave «Нет курса» on screen for up to a day just
    // because some other currency was fetched an hour ago.
    final latest = ref.read(latestAutoRateAtProvider);
    if (!_hasUnratedCurrency() &&
        latest != null &&
        now.toUtc().difference(latest) < rateStalenessThreshold) {
      return;
    }
    await refreshNow();
  }

  /// Whether some currency in use has no stored rate and is worth asking for.
  /// USD needs none: it is the pivot every rate is quoted against.
  bool _hasUnratedCurrency() {
    final known = {
      for (final rate in ref.read(ratesProvider).valueOrNull ?? const <Rate>[])
        rate.code.toUpperCase(),
      'USD',
      ..._unfetchable,
    };
    return ref
        .read(usedCurrencyCodesProvider)
        .any((code) => !known.contains(code));
  }

  /// Refreshes unconditionally — what «обновить сейчас» in settings calls.
  Future<void> refreshNow() async {
    if (_running) return;
    if (!await _awaitData()) return;

    final codes = ref.read(usedCurrencyCodesProvider);
    if (codes.isEmpty || (codes.length == 1 && codes.contains('USD'))) return;

    _running = true;
    state = const AsyncValue.loading();
    try {
      final fetched = await ref.read(rateFetcherProvider).fetch(codes);
      // Whatever the sources did not return is not going to appear on a retry;
      // remember it so it stops forcing a fetch on every resume. A code that
      // did come back is forgiven, in case it was a transient gap.
      _unfetchable
        ..removeAll(fetched.keys.map((code) => code.toUpperCase()))
        ..addAll(
          codes
              .map((code) => code.toUpperCase())
              .where((code) => code != 'USD' && !fetched.containsKey(code)),
        );
      await ref.read(ratesProvider.notifier).applyAuto(fetched);
      state = const AsyncValue.data(null);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    } finally {
      _running = false;
    }
  }

  /// Waits for the data the refresh decision depends on.
  ///
  /// On a cold start this runs while accounts, operations and rates are still
  /// loading; without waiting, the currency set reads empty and the refresh
  /// silently does nothing until the next resume.
  Future<bool> _awaitData() async {
    try {
      await ref.read(accountsProvider.future);
      await ref.read(opsProvider.future);
      await ref.read(ratesProvider.future);
      return true;
    } catch (error, stack) {
      // Nothing to refresh against — the screens surface the load failure.
      state = AsyncValue.error(error, stack);
      return false;
    }
  }
}

final rateRefreshProvider =
    NotifierProvider<RateRefreshController, AsyncValue<void>>(
      RateRefreshController.new,
    );

/// Drives [RateRefreshController] from the app lifecycle: once at start-up, then
/// on every return to the foreground.
class RateRefreshScope extends ConsumerStatefulWidget {
  final Widget child;

  const RateRefreshScope({super.key, required this.child});

  @override
  ConsumerState<RateRefreshScope> createState() => _RateRefreshScopeState();
}

class _RateRefreshScopeState extends ConsumerState<RateRefreshScope> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onResume: _refresh);
    // After the first frame: the rates provider has to be able to load its rows
    // before staleness can be judged.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    ref.read(rateRefreshProvider.notifier).refreshIfStale();
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
