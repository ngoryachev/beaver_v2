import '../models/planned_op.dart';
import 'occurrences.dart';
import 'project_balance.dart';

/// A run of occurrences of one operation on consecutive calendar days, folded
/// into a single row for the event list.
///
/// A lone occurrence is also a group, with [count] `== 1` and
/// `firstDate == lastDate`, so the UI has one data type for both shapes.
class ProjectionEventGroup {
  /// Date of the first occurrence in the run.
  final DateTime firstDate;

  /// Date of the last occurrence in the run — [firstDate] plus `count - 1` days.
  final DateTime lastDate;

  /// How many occurrences the run covers, one per calendar day.
  final int count;

  final PlannedOp op;

  /// Signed amount of *one* occurrence, in minor units of the operation's own
  /// currency.
  final int amountMinor;

  /// Same single occurrence in base-currency minor units, or `null` when the
  /// rate is missing — the group is still listed so the UI can flag it.
  final int? baseAmountMinor;

  const ProjectionEventGroup({
    required this.firstDate,
    required this.lastDate,
    required this.count,
    required this.op,
    required this.amountMinor,
    required this.baseAmountMinor,
  });

  /// Signed amount of the whole run in the operation's own currency.
  int get totalAmountMinor => amountMinor * count;

  /// Same total in base currency, or `null` when a single occurrence could not
  /// be converted.
  int? get totalBaseAmountMinor {
    final single = baseAmountMinor;
    return single == null ? null : single * count;
  }
}

/// Folds runs of the same operation on consecutive days in [events] into
/// groups, leaving every other occurrence as a one-element group.
///
/// Pure, and a single pass over [events]: a daily operation over a horizon
/// years out must not cost more than the events it already produced.
///
/// [events] is expected in `projectBalance`'s order — date, then title — and
/// that order is preserved: a group sits where its first occurrence sat, so
/// other operations firing inside its range keep their own rows and do not
/// break the run.
List<ProjectionEventGroup> groupConsecutiveEvents(
  List<ProjectionEvent> events,
) {
  final groups = <_OpenGroup>[];
  // Index of the run currently open for an operation, keyed by what makes two
  // occurrences interchangeable: the same operation at the same signed amount.
  final openByOp = <String, int>{};

  for (final event in events) {
    final key = '${event.op.id}|${event.amountMinor}';
    final openIndex = openByOp[key];
    final open = openIndex == null ? null : groups[openIndex];
    // Exactly one calendar day on: anything else — a gap, or a second
    // occurrence on the same day — starts a new run.
    if (open != null && daysBetween(open.lastDate, event.date) == 1) {
      open.lastDate = event.date;
      open.count++;
      continue;
    }
    openByOp[key] = groups.length;
    groups.add(_OpenGroup(event));
  }

  return [for (final group in groups) group.freeze()];
}

/// A group still being extended. Mutable only inside this file; callers see the
/// immutable [ProjectionEventGroup].
class _OpenGroup {
  final ProjectionEvent first;
  DateTime lastDate;
  int count = 1;

  _OpenGroup(this.first) : lastDate = first.date;

  ProjectionEventGroup freeze() => ProjectionEventGroup(
    firstDate: first.date,
    lastDate: lastDate,
    count: count,
    op: first.op,
    amountMinor: first.amountMinor,
    baseAmountMinor: first.baseAmountMinor,
  );
}
