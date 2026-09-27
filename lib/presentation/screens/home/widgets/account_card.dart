import 'package:flutter/material.dart';

import '../../../../domain/models/account.dart';
import '../../../../domain/models/currency.dart';
import '../../../format/money_format.dart';

/// One account on the home screen. Tapping it opens the balance editor.
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;

  /// Balance converted into the base currency, or `null` when no rate is known.
  /// Shown as a subtitle only when it differs from the account's own currency.
  final int? baseAmount;
  final String baseCurrency;

  const AccountCard({
    super.key,
    required this.account,
    required this.onTap,
    required this.baseAmount,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = Currency.byCode(account.currencyCode);
    final isForeign = currency.code != baseCurrency.toUpperCase();

    return Card(
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
        subtitle: isForeign
            ? Text(
                baseAmount == null
                    ? 'Нет курса ${currency.code}'
                    : '≈ ${formatMoney(baseAmount!, baseCurrency)}',
              )
            : null,
        trailing: Text(
          formatMoney(account.balance, account.currencyCode),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: account.balance < 0 ? theme.colorScheme.error : null,
          ),
        ),
      ),
    );
  }
}
