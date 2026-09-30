import 'package:flutter/material.dart';

import '../../../../domain/models/account.dart';
import '../../../../domain/models/currency.dart';
import '../../../format/money_format.dart';

/// One account on the home screen. Tapping it opens the balance editor.
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;

  /// Balance converted into the base currency, or `null` when it could not be
  /// converted. Shown as a subtitle only when it differs from the account's own
  /// currency.
  final int? baseAmount;
  final String baseCurrency;

  /// Whether a rate exists for both sides. Tells the two reasons [baseAmount]
  /// can be `null` apart: a missing rate the user can go and set, versus an
  /// amount too large to express — saying «Нет курса» for the second would send
  /// them to fix something that is not broken.
  final bool rateKnown;

  /// The active scenario leaves this account out of the total. The card stays
  /// tappable — the balance still needs editing — but is dimmed and labelled, so
  /// the headline figure above cannot look like it simply fails to add up.
  final bool excluded;

  const AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    required this.baseAmount,
    required this.baseCurrency,
    this.rateKnown = true,
    this.excluded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = Currency.byCode(account.currencyCode);
    final isForeign = currency.code != baseCurrency.toUpperCase();
    final notes = <String>[
      if (isForeign)
        baseAmount != null
            ? '≈ ${formatMoney(baseAmount!, baseCurrency)}'
            : rateKnown
            ? 'Слишком большая сумма'
            : 'Нет курса ${currency.code}',
      if (excluded) 'Не в сценарии',
    ];

    return Opacity(
      opacity: excluded ? 0.5 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              currency.symbol,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          title: Text(account.name),
          subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
          trailing: Text(
            formatMoney(account.balance, account.currencyCode),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: account.balance < 0 ? theme.colorScheme.error : null,
            ),
          ),
        ),
      ),
    );
  }
}
