import 'package:beaver_v2/data/in_memory/in_memory_accounts_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_planned_ops_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_rates_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_scenarios_repository.dart';
import 'package:beaver_v2/data/in_memory/in_memory_settings_repository.dart';
import 'package:beaver_v2/domain/models/account.dart';
import 'package:beaver_v2/domain/models/planned_op.dart';
import 'package:beaver_v2/domain/models/rate.dart';
import 'package:beaver_v2/domain/models/scenario.dart';
import 'package:beaver_v2/domain/models/user_settings.dart';
import 'package:beaver_v2/presentation/format/money_format.dart';
import 'package:beaver_v2/presentation/providers/repo_providers.dart';
import 'package:beaver_v2/presentation/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The operations list lives on the home screen as a section of collapsible
/// category groups. These are the old `OpsListScreen` tests plus what the move
/// added: the collapsed/expanded state, the per-group monthly estimate and the
/// base-currency equivalent next to a foreign amount.
const _userId = 'u1';

PlannedOp _op({
  required String id,
  required String title,
  required int amount,
  required OpCategory category,
  OpKind kind = OpKind.expense,
  Schedule schedule = Schedule.monthly,
  String code = 'RUB',
  bool enabled = true,
  DateTime? startDate,
}) => PlannedOp(
  id: id,
  userId: _userId,
  title: title,
  amount: amount,
  currencyCode: code,
  kind: kind,
  category: category,
  schedule: schedule,
  startDate: startDate ?? DateTime(2020, 9, 1),
  enabled: enabled,
);

Rate _rate(String code, double perUsd) => Rate(
  userId: _userId,
  code: code,
  ratePerUsd: perUsd,
  source: RateSource.auto,
  updatedAt: DateTime.now().toUtc(),
);

Future<InMemoryPlannedOpsRepository> _pumpHome(
  WidgetTester tester,
  List<PlannedOp> ops, {
  List<Rate> rates = const [],
  Size size = const Size(1200, 3000),
}) async {
  final repository = InMemoryPlannedOpsRepository(ops);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_userId),
        accountsRepositoryProvider.overrideWithValue(
          InMemoryAccountsRepository(const [
            Account(
              id: 'a1',
              userId: _userId,
              name: 'Карта',
              currencyCode: 'RUB',
              balance: 100000,
            ),
          ]),
        ),
        plannedOpsRepositoryProvider.overrideWithValue(repository),
        scenariosRepositoryProvider.overrideWithValue(
          InMemoryScenariosRepository([
            Scenario(id: 's1', userId: _userId, name: 'Все', isDefault: true),
          ]),
        ),
        ratesRepositoryProvider.overrideWithValue(
          InMemoryRatesRepository(rates),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(
            const UserSettings(userId: _userId, baseCurrency: 'RUB'),
          ),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _expand(WidgetTester tester, String category) async {
  await tester.tap(find.text(category));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('an empty list explains what to do', (tester) async {
    await _pumpHome(tester, const []);
    expect(find.textContaining('Пока нет операций'), findsOneWidget);
  });

  testWidgets('groups are collapsed until the header is tapped', (
    tester,
  ) async {
    await _pumpHome(tester, [
      _op(
        id: 'o1',
        title: 'Продукты',
        amount: 1500000,
        category: OpCategory.food,
      ),
    ]);

    // The group is there, its contents are not.
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Продукты'), findsNothing);

    await _expand(tester, 'Еда');
    expect(find.text('Продукты'), findsOneWidget);

    // Tapping again closes it.
    await _expand(tester, 'Еда');
    expect(find.text('Продукты'), findsNothing);
  });

  testWidgets('operations are grouped by category in enum order', (
    tester,
  ) async {
    await _pumpHome(tester, [
      _op(
        id: 'o1',
        title: 'Зарплата',
        amount: 20000000,
        category: OpCategory.salary,
        kind: OpKind.income,
      ),
      _op(
        id: 'o2',
        title: 'Продукты',
        amount: 1500000,
        category: OpCategory.food,
      ),
      _op(id: 'o3', title: 'Кафе', amount: 300000, category: OpCategory.food),
      _op(
        id: 'o4',
        title: 'Квартира',
        amount: 4000000,
        category: OpCategory.housing,
      ),
    ]);

    // «Еда» is declared before «Квартплата», which is declared before
    // «Зарплата», whatever order the repository returned the rows in.
    final foodY = tester.getTopLeft(find.text('Еда')).dy;
    final housingY = tester.getTopLeft(find.text('Квартплата')).dy;
    final salaryY = tester.getTopLeft(find.text('Зарплата')).dy;
    expect(foodY, lessThan(housingY));
    expect(housingY, lessThan(salaryY));

    // Both food operations sit under the single «Еда» heading.
    await _expand(tester, 'Еда');
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
  });

  group('the collapsed monthly estimate', () {
    testWidgets('sums the group per month and drops out when expanded', (
      tester,
    ) async {
      await _pumpHome(tester, [
        // 15 000 ₽ a month plus 1 000 ₽ a week (× 4.35 = 4 350 ₽).
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
        _op(
          id: 'o2',
          title: 'Кафе',
          amount: 100000,
          category: OpCategory.food,
          schedule: Schedule.weekly,
        ),
      ]);

      expect(
        find.textContaining('−${formatMoneyCompact(1935000, 'RUB')} / мес'),
        findsOneWidget,
      );

      await _expand(tester, 'Еда');
      expect(find.textContaining('/ мес'), findsNothing);
    });

    testWidgets('an income group is signed the other way', (tester) async {
      await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Зарплата',
          amount: 20000000,
          category: OpCategory.salary,
          kind: OpKind.income,
        ),
      ]);

      expect(
        find.textContaining('+${formatMoneyCompact(20000000, 'RUB')} / мес'),
        findsOneWidget,
      );
    });

    testWidgets('a disabled operation is left out of the estimate', (
      tester,
    ) async {
      await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
        _op(
          id: 'o2',
          title: 'Подписка',
          amount: 500000,
          category: OpCategory.food,
          enabled: false,
        ),
      ]);

      expect(
        find.textContaining('−${formatMoneyCompact(1500000, 'RUB')} / мес'),
        findsOneWidget,
      );
    });

    testWidgets('a group whose rate is missing says so', (tester) async {
      await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Хостинг',
          amount: 1000,
          category: OpCategory.software,
          code: 'EUR',
        ),
      ]);

      expect(find.textContaining('нет курса'), findsOneWidget);
    });
  });

  group('a foreign amount', () {
    testWidgets('shows the base-currency equivalent', (tester) async {
      await _pumpHome(
        tester,
        [
          _op(
            id: 'o1',
            title: 'Хостинг',
            amount: 1000,
            category: OpCategory.software,
            code: 'EUR',
          ),
        ],
        rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      );
      await _expand(tester, 'Software');

      // 10 € ÷ 0.9 × 90 = 1 000 ₽.
      expect(find.text('−${formatMoney(1000, 'EUR')}'), findsOneWidget);
      expect(find.text('≈ ${formatMoney(100000, 'RUB')}'), findsOneWidget);
    });

    testWidgets('names the currency whose rate is missing', (tester) async {
      await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Хостинг',
          amount: 1000,
          category: OpCategory.software,
          code: 'EUR',
        ),
      ]);
      await _expand(tester, 'Software');

      expect(find.text('Нет курса EUR'), findsOneWidget);
      expect(find.textContaining('≈'), findsNothing);
    });

    testWidgets('an amount in the base currency gets no second line', (
      tester,
    ) async {
      await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
      ]);
      await _expand(tester, 'Еда');

      expect(find.text('−${formatMoney(1500000, 'RUB')}'), findsOneWidget);
      expect(find.textContaining('≈'), findsNothing);
      expect(find.textContaining('Нет курса'), findsNothing);
    });
  });

  testWidgets('the switch turns an operation off and stores it', (
    tester,
  ) async {
    final repository = await _pumpHome(tester, [
      _op(
        id: 'o1',
        title: 'Продукты',
        amount: 1500000,
        category: OpCategory.food,
      ),
    ]);
    await _expand(tester, 'Еда');

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final stored = await repository.getAll();
    expect(stored.single.enabled, isFalse);
    // Turning an operation off must not touch anything else about it.
    expect(stored.single.amount, 1500000);
  });

  testWidgets('a disabled operation is still listed', (tester) async {
    await _pumpHome(tester, [
      _op(
        id: 'o1',
        title: 'Подписка',
        amount: 99900,
        category: OpCategory.services,
        enabled: false,
      ),
    ]);
    await _expand(tester, 'Услуги');

    expect(find.text('Подписка'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('lays out on a phone-sized screen without overflowing', (
    tester,
  ) async {
    // The widest label in the app next to an estimate, and a foreign amount
    // with its converted second line — the two things the row has to fit.
    await _pumpHome(
      tester,
      [
        _op(
          id: 'o1',
          title: 'Электричество и вода',
          amount: 1234567,
          category: OpCategory.utilities,
        ),
        _op(
          id: 'o2',
          title: 'Хостинг',
          amount: 199900,
          category: OpCategory.utilities,
          code: 'EUR',
        ),
      ],
      rates: [_rate('RUB', 90), _rate('EUR', 0.9)],
      size: const Size(390, 844),
    );

    expect(find.text('Коммунальные платежи'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _expand(tester, 'Коммунальные платежи');
    expect(find.text('Хостинг'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the longest estimate still fits a phone-sized header', (
    tester,
  ) async {
    // The same row as above, minus the rates: the estimate then carries the
    // «· нет курса» tail, which is the longest the header can ever get. The
    // category label is `Expanded` and can ellipsise, but the estimate is a
    // plain `Text` with `softWrap: false`, so nothing gives way on its side.
    await _pumpHome(
      tester,
      [
        _op(
          id: 'o1',
          title: 'Электричество и вода',
          amount: 1500000,
          category: OpCategory.utilities,
        ),
        _op(
          id: 'o2',
          title: 'Хостинг',
          amount: 199900,
          category: OpCategory.utilities,
          code: 'EUR',
        ),
      ],
      size: const Size(390, 844),
    );

    expect(find.textContaining('нет курса'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the collapsed header overflows once the estimate is long',
    );
  });

  group('swipe to delete', () {
    testWidgets('asks first, then removes the operation', (tester) async {
      final repository = await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
        _op(
          id: 'o2',
          title: 'Кафе',
          amount: 300000,
          category: OpCategory.food,
        ),
      ]);
      await _expand(tester, 'Еда');

      await tester.drag(find.text('Кафе'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('Удалить операцию?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      final stored = await repository.getAll();
      expect(stored.map((op) => op.id), ['o1']);
      expect(find.text('Кафе'), findsNothing);
      expect(find.text('Продукты'), findsOneWidget);
    });

    testWidgets('cancelling keeps the operation', (tester) async {
      final repository = await _pumpHome(tester, [
        _op(
          id: 'o1',
          title: 'Продукты',
          amount: 1500000,
          category: OpCategory.food,
        ),
      ]);
      await _expand(tester, 'Еда');

      await tester.drag(find.text('Продукты'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      await tester.pumpAndSettle();

      expect((await repository.getAll()).length, 1);
      expect(find.text('Продукты'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
