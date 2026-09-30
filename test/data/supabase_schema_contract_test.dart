import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Supabase repositories are the one layer no other test can exercise: they
/// need a live PostgREST, so they are excluded from the widget tests by
/// overriding the repository providers with the in-memory ones. Their whole job
/// is to name tables, columns and RPC arguments correctly, and a single typo
/// there fails only in production, at runtime, as a PostgREST 400.
///
/// So this checks the contract statically: every identifier the Dart side sends
/// to the database has to exist in `001_beaver_schema.sql`, and every column the
/// migration declares `NOT NULL` without a default has to be written.
void main() {
  final root = Directory.current.path;
  final schema = File(
    '$root/supabase/migrations/001_beaver_schema.sql',
  ).readAsStringSync();

  final tables = _parseTables(schema);

  group('the migration declares the tables the app uses', () {
    for (final name in const [
      'user_settings',
      'accounts',
      'planned_ops',
      'scenarios',
      'rates',
    ]) {
      test(name, () => expect(tables.keys, contains(name)));
    }
  });

  group('every column a repository names exists in its table', () {
    final repositories = <String, String>{
      'accounts': 'supabase_accounts_repository.dart',
      'planned_ops': 'supabase_planned_ops_repository.dart',
      'scenarios': 'supabase_scenarios_repository.dart',
      'rates': 'supabase_rates_repository.dart',
      'user_settings': 'supabase_settings_repository.dart',
    };

    repositories.forEach((table, fileName) {
      final source = File(
        '$root/lib/data/supabase/$fileName',
      ).readAsStringSync();
      final columns = tables[table]!;

      test('$fileName targets only $table', () {
        final targeted = RegExp(
          r"""\.from\(\s*'([a-z_]+)'""",
        ).allMatches(source).map((m) => m.group(1)).toSet();
        expect(targeted, {table});
      });

      test('$fileName writes only real columns of $table', () {
        // Guard against a silent pass: an extraction that found nothing would
        // make every loop below vacuous.
        expect(_rowKeys(source), isNotEmpty);
        expect(columns, isNotEmpty);
        for (final key in _rowKeys(source)) {
          expect(
            columns,
            contains(key),
            reason: '$fileName writes "$key", which $table does not have',
          );
        }
      });

      test('$fileName reads only real columns of $table', () {
        expect(_jsonKeys(source), isNotEmpty);
        for (final key in _jsonKeys(source)) {
          expect(
            columns,
            contains(key),
            reason: '$fileName reads "$key", which $table does not have',
          );
        }
      });

      test('$fileName filters and orders by real columns of $table', () {
        expect(_filterKeys(source), isNotEmpty);
        for (final key in _filterKeys(source)) {
          expect(
            columns,
            contains(key),
            reason: '$fileName queries "$key", which $table does not have',
          );
        }
      });

      test('$fileName supplies every column $table requires', () {
        final written = _rowKeys(source);
        for (final required in _requiredColumns(schema, table)) {
          expect(
            written,
            contains(required),
            reason:
                '$table.$required is NOT NULL without a default, so an insert '
                'from $fileName would be rejected',
          );
        }
      });
    });
  });

  group('the transfer RPC', () {
    final source = File(
      '$root/lib/data/supabase/supabase_accounts_repository.dart',
    ).readAsStringSync();

    test('is called with the argument names the function declares', () {
      final declared = RegExp(
        r'CREATE OR REPLACE FUNCTION transfer\(([^)]*)\)',
      ).firstMatch(schema)!.group(1)!;
      final declaredNames = RegExp(r'([a-z_]+)\s+(UUID|BIGINT)')
          .allMatches(declared)
          .map((m) => m.group(1)!)
          .toSet();

      final call = RegExp(
        r"""rpc\(\s*'transfer',\s*params:\s*\{(.*?)\},""",
        dotAll: true,
      ).firstMatch(source)!.group(1)!;
      final passed = RegExp(
        r"""'([a-z_]+)':""",
      ).allMatches(call).map((m) => m.group(1)!).toSet();

      expect(declaredNames, isNotEmpty);
      expect(passed, declaredNames);
    });

    test('is granted to the authenticated role, or PostgREST cannot call it', () {
      expect(
        schema,
        contains('GRANT EXECUTE ON FUNCTION transfer'),
      );
    });
  });

  group('row-level security', () {
    for (final table in const [
      'user_settings',
      'accounts',
      'planned_ops',
      'scenarios',
      'rates',
    ]) {
      test('$table is protected by four owner policies', () {
        expect(
          schema,
          contains('ALTER TABLE $table ENABLE ROW LEVEL SECURITY'),
          reason: 'without this the policies below are never applied',
        );
        for (final action in const ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
          expect(
            schema,
            contains('ON $table FOR $action'),
            reason: '$table has no $action policy',
          );
        }
      });

      test('$table cascades when the user is deleted', () {
        expect(
          tables[table]!['user_id'],
          contains('REFERENCES auth.users(id) ON DELETE CASCADE'),
        );
      });

      test('$table is indexed by user_id', () {
        expect(schema, contains('ON $table(user_id)'));
      });
    }
  });
}

/// Maps each `CREATE TABLE` to its columns, keeping each column's raw
/// definition so the references and defaults can be inspected.
Map<String, Map<String, String>> _parseTables(String schema) {
  final tables = <String, Map<String, String>>{};
  final pattern = RegExp(
    r'CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\n\);',
    dotAll: true,
  );
  for (final match in pattern.allMatches(schema)) {
    tables[match.group(1)!] = _parseColumns(match.group(2)!);
  }
  return tables;
}

/// Splits a table body into `column -> definition`, at top-level commas only —
/// a `CHECK (a IN ('x', 'y'))` must not be mistaken for a column boundary.
Map<String, String> _parseColumns(String body) {
  final columns = <String, String>{};
  // Comments first: they are full of commas, and a comma inside one would
  // otherwise look like a column boundary.
  final stripped = body
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'\s*--.*$'), ''))
      .join('\n');
  var depth = 0;
  final current = StringBuffer();
  final parts = <String>[];
  for (final rune in stripped.runes) {
    final char = String.fromCharCode(rune);
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      parts.add(current.toString());
      current.clear();
      continue;
    }
    current.write(char);
  }
  parts.add(current.toString());

  for (final part in parts) {
    final cleaned = part.split('\n').join(' ').replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) continue;
    // Table-level constraints are not columns.
    if (cleaned.startsWith('CONSTRAINT')) continue;
    final name = cleaned.split(RegExp(r'\s+')).first;
    columns[name] = cleaned;
  }
  return columns;
}

/// Columns an INSERT must supply: `NOT NULL` and no `DEFAULT`. `created_at` and
/// `updated_at` always have one, `id` is generated — what is left is the payload
/// the repository is responsible for.
Set<String> _requiredColumns(String schema, String table) {
  final columns = _parseTables(schema)[table]!;
  return {
    for (final entry in columns.entries)
      if (entry.value.contains('NOT NULL') &&
          !entry.value.contains('DEFAULT') &&
          !entry.value.contains('PRIMARY KEY'))
        entry.key,
  };
}

/// Column names written by a `_toRow` map literal.
Set<String> _rowKeys(String source) {
  final body = RegExp(
    r'Map<String, dynamic> _toRow\([^)]*\) => \{(.*?)\n  \};',
    dotAll: true,
  ).firstMatch(source);
  if (body == null) return const {};
  return RegExp(
    r"""'([a-z_]+)':""",
  ).allMatches(body.group(1)!).map((m) => m.group(1)!).toSet();
}

/// Column names read back as `json['...']`.
Set<String> _jsonKeys(String source) => RegExp(r"""json\['([a-z_]+)'\]""")
    .allMatches(source)
    .map((m) => m.group(1)!)
    .toSet();

/// Column names used in `.eq(...)` filters and `.order(...)` clauses.
Set<String> _filterKeys(String source) => RegExp(
  r"""\.(?:eq|order)\(\s*'([a-z_]+)'""",
).allMatches(source).map((m) => m.group(1)!).toSet();
