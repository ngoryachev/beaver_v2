import 'package:flutter/material.dart';

import '../../../domain/models/planned_op.dart';

/// Russian labels and icons for the closed enums, kept out of the screens so the
/// list and the editor cannot disagree.
String categoryLabel(OpCategory category) => switch (category) {
  OpCategory.food => 'Еда',
  OpCategory.shopping => 'Покупки',
  OpCategory.services => 'Услуги',
  OpCategory.housing => 'Квартплата',
  OpCategory.utilities => 'Коммунальные платежи',
  OpCategory.health => 'Здоровье',
  OpCategory.education => 'Обучение',
  // Not translated on purpose: this is what the user calls the category.
  OpCategory.software => 'Software',
  OpCategory.travel => 'Путешествия',
  OpCategory.fun => 'Развлечения',
  OpCategory.debt => 'Кредиты',
  OpCategory.salary => 'Зарплата',
  OpCategory.other => 'Прочее',
};

IconData categoryIcon(OpCategory category) => switch (category) {
  OpCategory.food => Icons.restaurant,
  OpCategory.shopping => Icons.shopping_bag_outlined,
  OpCategory.services => Icons.build_outlined,
  OpCategory.housing => Icons.home_outlined,
  OpCategory.utilities => Icons.bolt_outlined,
  OpCategory.health => Icons.favorite_outline,
  OpCategory.education => Icons.school_outlined,
  OpCategory.software => Icons.apps_outlined,
  OpCategory.travel => Icons.flight_takeoff,
  OpCategory.fun => Icons.celebration_outlined,
  OpCategory.debt => Icons.account_balance_outlined,
  OpCategory.salary => Icons.payments_outlined,
  OpCategory.other => Icons.category_outlined,
};

String scheduleLabel(Schedule schedule) => switch (schedule) {
  Schedule.once => 'Один раз',
  Schedule.daily => 'Каждый день',
  Schedule.weekly => 'Каждую неделю',
  Schedule.biweekly => 'Раз в две недели',
  Schedule.monthly => 'Каждый месяц',
  Schedule.yearly => 'Каждый год',
};

String kindLabel(OpKind kind) => switch (kind) {
  OpKind.income => 'Доход',
  OpKind.expense => 'Расход',
};
