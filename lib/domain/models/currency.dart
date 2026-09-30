/// A currency the app can hold money in. The list is static: there is no
/// per-user currency catalogue, so codes never need to be fetched.
class Currency {
  final String code;
  final String symbol;

  /// Minor-unit digits. JPY has none, so its amounts are whole yen.
  final int decimals;

  const Currency({required this.code, required this.symbol, this.decimals = 2});

  static const rub = Currency(code: 'RUB', symbol: '₽');
  static const usd = Currency(code: 'USD', symbol: '\$');
  static const eur = Currency(code: 'EUR', symbol: '€');
  static const gbp = Currency(code: 'GBP', symbol: '£');
  static const kzt = Currency(code: 'KZT', symbol: '₸');
  static const gel = Currency(code: 'GEL', symbol: '₾');
  static const amd = Currency(code: 'AMD', symbol: '֏');
  static const rsd = Currency(code: 'RSD', symbol: 'din');
  static const tryLira = Currency(code: 'TRY', symbol: '₺');
  static const aed = Currency(code: 'AED', symbol: 'AED');
  static const cny = Currency(code: 'CNY', symbol: '¥');
  static const jpy = Currency(code: 'JPY', symbol: '¥', decimals: 0);
  static const thb = Currency(code: 'THB', symbol: '฿');
  static const byn = Currency(code: 'BYN', symbol: 'Br');
  static const uah = Currency(code: 'UAH', symbol: '₴');

  /// Every currency the UI offers, in the order it is shown.
  static const all = <Currency>[
    rub,
    usd,
    eur,
    gbp,
    kzt,
    gel,
    amd,
    rsd,
    tryLira,
    aed,
    cny,
    jpy,
    thb,
    byn,
    uah,
  ];

  /// Looks a currency up by code; unknown codes fall back to a 2-decimal
  /// placeholder so a row written by a newer build never crashes an older one.
  static Currency byCode(String code) {
    final upper = code.toUpperCase();
    for (final currency in all) {
      if (currency.code == upper) return currency;
    }
    return Currency(code: upper, symbol: upper);
  }

  static int decimalsOf(String code) => byCode(code).decimals;

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}
