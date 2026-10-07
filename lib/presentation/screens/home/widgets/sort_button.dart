import 'package:flutter/material.dart';

import '../../../../domain/models/amount_sort.dart';

/// Flips a home-screen section between «по убыванию» and «по возрастанию»
/// суммы. The arrow shows the current direction, the tooltip names it.
class SortButton extends StatelessWidget {
  final AmountSort direction;
  final VoidCallback onPressed;

  const SortButton({
    super.key,
    required this.direction,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final desc = direction == AmountSort.desc;
    return IconButton(
      icon: Icon(desc ? Icons.arrow_downward : Icons.arrow_upward, size: 20),
      tooltip: desc ? 'По убыванию суммы' : 'По возрастанию суммы',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}
