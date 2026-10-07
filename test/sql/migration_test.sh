#!/usr/bin/env bash
# Verifies supabase/migrations/001_beaver_schema.sql against a throwaway Postgres.
#
# `flutter test` cannot reach SQL, so the schema — its CHECKs, its RLS policies
# and the `transfer()` function — would otherwise ship unverified. This script
# applies the migration twice (idempotency), then drives it as two different
# authenticated users.
#
# Opt-in: needs docker and the postgres image. Skips with exit code 0 when either
# is unavailable, so it is safe to call from a pipeline that has neither.
#
# Usage: test/sql/migration_test.sh
set -uo pipefail

cd "$(dirname "$0")/../.."

IMAGE="${POSTGRES_IMAGE:-postgres:16-alpine}"
CONTAINER="beaver-migration-test-$$"

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker недоступен"
  exit 0
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "SKIP: нет образа $IMAGE (docker pull $IMAGE)"
  exit 0
fi

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=pg "$IMAGE" >/dev/null
# Over TCP, not the socket: on first start the image runs a temporary
# socket-only server for initdb and then restarts, and a socket check can catch
# that temporary one and race the restart.
for _ in $(seq 1 30); do
  docker exec "$CONTAINER" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 && break
  sleep 1
done

psql_file() { docker exec -i "$CONTAINER" psql -U postgres -d postgres "$@"; }

failures=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1 — ожидалось «$2», получено «$3»" >&2
    failures=$((failures + 1))
  fi
}

# --- the auth schema Supabase supplies and this migration builds on -----------
psql_file -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$ LANGUAGE sql STABLE;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT USAGE ON SCHEMA public, auth TO authenticated;
SQL

echo "== применяется миграция"
if ! psql_file -v ON_ERROR_STOP=1 -q < supabase/migrations/001_beaver_schema.sql; then
  echo "  FAIL: миграция не применилась" >&2
  exit 1
fi
echo "  ok: применилась"

echo "== повторное применение (идемпотентность)"
if ! psql_file -v ON_ERROR_STOP=1 -q < supabase/migrations/001_beaver_schema.sql 2>/dev/null; then
  echo "  FAIL: повторный прогон упал" >&2
  failures=$((failures + 1))
else
  echo "  ok: повторный прогон чистый"
fi

# --- the upgrade path: a database that already has the tables ----------------
# `CREATE TABLE IF NOT EXISTS` is a no-op there, so widening `category` and
# `schedule` and adding the horizon columns rests entirely on the ALTERs. The run
# above only proves the fresh path, so this one rebuilds the *previous* shape of
# the schema in a throwaway database and applies the migration over it.
echo "== применение на уже развёрнутую базу"
psql_file -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE upgrade" >/dev/null 2>&1
psql_upgrade() { docker exec -i "$CONTAINER" psql -U postgres -d upgrade "$@"; }

psql_upgrade -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$ LANGUAGE sql STABLE;
GRANT USAGE ON SCHEMA public, auth TO authenticated;
SQL
psql_upgrade -v ON_ERROR_STOP=1 -q < supabase/migrations/001_beaver_schema.sql >/dev/null 2>&1
# Roll the closed sets and the horizon columns back to what shipped before, and
# leave a row behind: a NOT NULL column added to a populated table has to carry a
# default, and the user's base currency must survive the upgrade untouched.
psql_upgrade -v ON_ERROR_STOP=1 -q <<'SQL'
ALTER TABLE planned_ops DROP CONSTRAINT planned_ops_category_check;
ALTER TABLE planned_ops ADD CONSTRAINT planned_ops_category_check CHECK (
  category IN ('food','shopping','services','travel','fun','debt','salary','other'));
ALTER TABLE planned_ops DROP CONSTRAINT planned_ops_schedule_check;
ALTER TABLE planned_ops ADD CONSTRAINT planned_ops_schedule_check CHECK (
  schedule IN ('once','daily','weekly','monthly','yearly'));
ALTER TABLE user_settings DROP COLUMN forecast_preset;
ALTER TABLE user_settings DROP COLUMN forecast_custom_date;
ALTER TABLE user_settings DROP COLUMN accounts_sort;
ALTER TABLE user_settings DROP COLUMN ops_sort;
INSERT INTO auth.users(id) VALUES ('11111111-1111-1111-1111-111111111111');
INSERT INTO user_settings(user_id, base_currency)
  VALUES ('11111111-1111-1111-1111-111111111111', 'EUR');
SQL

if ! psql_upgrade -v ON_ERROR_STOP=1 -q < supabase/migrations/001_beaver_schema.sql 2>/dev/null; then
  echo "  FAIL: миграция не применилась на развёрнутую базу" >&2
  failures=$((failures + 1))
else
  echo "  ok: применилась"
fi
check "старая строка настроек получила горизонт по умолчанию" "plus30|EUR" \
  "$(psql_upgrade -qtAX -c "SELECT forecast_preset || '|' || base_currency FROM user_settings")"
if psql_upgrade -v ON_ERROR_STOP=1 -q -c "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date,category) VALUES ('11111111-1111-1111-1111-111111111111','t',1,'RUB','expense','biweekly','2026-01-01','software')" >/dev/null 2>&1; then
  echo "  ok: расширенные category и schedule приняты"
else
  echo "  FAIL: ALTER не расширил category/schedule на развёрнутой базе" >&2
  failures=$((failures + 1))
fi
if psql_upgrade -v ON_ERROR_STOP=1 -q -c "UPDATE user_settings SET forecast_preset='quarter'" >/dev/null 2>&1; then
  echo "  FAIL: forecast_preset без CHECK на развёрнутой базе" >&2
  failures=$((failures + 1))
else
  echo "  ok: мусорный forecast_preset отклонён"
fi
check "старая строка настроек получила сортировку по умолчанию" "desc|desc" \
  "$(psql_upgrade -qtAX -c "SELECT accounts_sort || '|' || ops_sort FROM user_settings")"
for column in accounts_sort ops_sort; do
  if psql_upgrade -v ON_ERROR_STOP=1 -q -c "UPDATE user_settings SET $column='sideways'" >/dev/null 2>&1; then
    echo "  FAIL: $column без CHECK на развёрнутой базе" >&2
    failures=$((failures + 1))
  else
    echo "  ok: мусорный $column отклонён"
  fi
done

psql_file -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO auth.users(id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') ON CONFLICT DO NOTHING;
INSERT INTO accounts(id,user_id,name,currency_code,balance) VALUES
  ('aaaa1111-1111-1111-1111-111111111111','11111111-1111-1111-1111-111111111111','Карта','RUB',100000),
  ('aaaa2222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','Копилка','USD',5000),
  ('bbbb3333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222','Чужой','RUB',999);
GRANT SELECT,INSERT,UPDATE,DELETE
  ON accounts, planned_ops, scenarios, rates, user_settings TO authenticated;
SQL

# `rejects` runs one statement as superuser and expects it to be refused.
rejects() { # rejects <description> <sql>
  if psql_file -v ON_ERROR_STOP=1 -q -c "$2" >/dev/null 2>&1; then
    echo "  FAIL: $1 — запись прошла, а должна была быть отклонена" >&2
    failures=$((failures + 1))
  else
    echo "  ok: $1"
  fi
}
accepts() { # accepts <description> <sql>
  if psql_file -v ON_ERROR_STOP=1 -q -c "$2" >/dev/null 2>&1; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1 — запись отклонена, а должна была пройти" >&2
    failures=$((failures + 1))
  fi
}

U1=11111111-1111-1111-1111-111111111111

echo "== CHECK-и"
rejects "код валюты не в верхнем регистре" \
  "INSERT INTO accounts(user_id,name,currency_code) VALUES ('$U1','x','rub')"
rejects "пустое название счёта" \
  "INSERT INTO accounts(user_id,name,currency_code) VALUES ('$U1','   ','RUB')"
rejects "amount = 0" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date) VALUES ('$U1','t',0,'RUB','expense','daily','2026-01-01')"
rejects "недопустимый kind" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date) VALUES ('$U1','t',1,'RUB','transfer','daily','2026-01-01')"
rejects "недопустимый schedule" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date) VALUES ('$U1','t',1,'RUB','expense','hourly','2026-01-01')"
rejects "недопустимая category" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date,category) VALUES ('$U1','t',1,'RUB','expense','daily','2026-01-01','rent')"
# The CHECKs are re-stated by ALTER after the CREATE TABLE, so these also prove
# the ALTER landed and did not narrow the set.
accepts "schedule = biweekly" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date) VALUES ('$U1','раз в две недели',1,'RUB','expense','biweekly','2026-01-01')"
for category in housing utilities health education software travel debt personal_debt alimony taxes; do
  accepts "category = $category" \
    "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date,category) VALUES ('$U1','t',1,'RUB','expense','monthly','2026-01-01','$category')"
done
rejects "end_date раньше start_date" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date,end_date) VALUES ('$U1','t',1,'RUB','expense','daily','2026-01-10','2026-01-09')"
accepts "end_date равна start_date" \
  "INSERT INTO planned_ops(user_id,title,amount,currency_code,kind,schedule,start_date,end_date) VALUES ('$U1','ok',1,'RUB','expense','once','2026-01-10','2026-01-10')"
rejects "недопустимый source курса" \
  "INSERT INTO rates(user_id,code,rate_per_usd,source) VALUES ('$U1','EUR',90,'cbr')"
rejects "нулевой курс" \
  "INSERT INTO rates(user_id,code,rate_per_usd) VALUES ('$U1','EUR',0)"
accepts "первая строка курса" \
  "INSERT INTO rates(user_id,code,rate_per_usd) VALUES ('$U1','RUB',90)"
rejects "вторая строка того же курса (unique user_id, code)" \
  "INSERT INTO rates(user_id,code,rate_per_usd) VALUES ('$U1','RUB',91)"
accepts "сценарий по умолчанию" \
  "INSERT INTO scenarios(user_id,name,is_default) VALUES ('$U1','Все',true)"
rejects "второй сценарий по умолчанию" \
  "INSERT INTO scenarios(user_id,name,is_default) VALUES ('$U1','Другой',true)"
accepts "настройки с горизонтом прогноза" \
  "INSERT INTO user_settings(user_id,base_currency,forecast_preset,forecast_custom_date) VALUES ('$U1','RUB','custom','2026-05-01')"
rejects "недопустимый forecast_preset" \
  "UPDATE user_settings SET forecast_preset='quarter' WHERE user_id='$U1'"

# The ALTERs that widen `category` and `schedule` on an already deployed
# database name the constraints explicitly, so the names have to be the ones
# Postgres actually used for the inline CHECKs.
echo "== имена ограничений, которые пересоздаёт миграция"
for constraint in planned_ops_category_check planned_ops_schedule_check \
  user_settings_forecast_preset_check; do
  check "$constraint существует" "1" \
    "$(psql_file -qtAX -c "SELECT count(*) FROM pg_constraint WHERE conname='$constraint'")"
done

echo "== триггер updated_at"
touched=$(psql_file -qtAX -c "UPDATE accounts SET name='Карта 2' WHERE id='aaaa1111-1111-1111-1111-111111111111'; SELECT updated_at > created_at FROM accounts WHERE id='aaaa1111-1111-1111-1111-111111111111'")
check "updated_at подтянулся при UPDATE" "t" "$touched"

# Everything below runs as `authenticated` with a JWT subject, so RLS applies.
as_user() { # as_user <uuid> <sql>
  psql_file -qtAX -c "SET ROLE authenticated; SET request.jwt.claim.sub = '$1'; $2"
}
as_user_fails() { # as_user_fails <description> <uuid> <sql>
  if as_user "$2" "$3" >/dev/null 2>&1; then
    echo "  FAIL: $1 — прошло, а должно было быть отклонено" >&2
    failures=$((failures + 1))
  else
    echo "  ok: $1"
  fi
}

echo "== RLS"
check "видит только свои счета" "2" "$(as_user "$U1" 'SELECT count(*) FROM accounts')"
check "чужой счёт не виден" "0" \
  "$(as_user "$U1" "SELECT count(*) FROM accounts WHERE id='bbbb3333-3333-3333-3333-333333333333'")"
as_user_fails "нельзя вставить строку другому пользователю" "$U1" \
  "INSERT INTO accounts(user_id,name,currency_code) VALUES ('22222222-2222-2222-2222-222222222222','Взлом','RUB')"
# RETURNING, not the command tag: `psql -qtAX` prints no «UPDATE n» line.
check "UPDATE чужой строки не задевает ни одной" "0" \
  "$(as_user "$U1" "WITH touched AS (UPDATE accounts SET balance=0 WHERE id='bbbb3333-3333-3333-3333-333333333333' RETURNING 1) SELECT count(*) FROM touched")"

echo "== transfer()"
as_user "$U1" "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','aaaa2222-2222-2222-2222-222222222222',10000,100)" >/dev/null
check "списано с источника" "90000" \
  "$(as_user "$U1" "SELECT balance FROM accounts WHERE id='aaaa1111-1111-1111-1111-111111111111'")"
check "зачислено получателю по своей сумме" "5100" \
  "$(as_user "$U1" "SELECT balance FROM accounts WHERE id='aaaa2222-2222-2222-2222-222222222222'")"
as_user_fails "перевод на тот же счёт" "$U1" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','aaaa1111-1111-1111-1111-111111111111',1,1)"
as_user_fails "нулевая сумма списания" "$U1" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','aaaa2222-2222-2222-2222-222222222222',0,1)"
as_user_fails "отрицательная сумма зачисления" "$U1" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','aaaa2222-2222-2222-2222-222222222222',1,-5)"
as_user_fails "перевод на чужой счёт" "$U1" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','bbbb3333-3333-3333-3333-333333333333',100,100)"
as_user_fails "перевод с чужого счёта" "$U1" \
  "SELECT transfer('bbbb3333-3333-3333-3333-333333333333','aaaa1111-1111-1111-1111-111111111111',100,100)"
as_user_fails "перевод на несуществующий счёт" "$U1" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','dddd4444-4444-4444-4444-444444444444',100,100)"
as_user_fails "перевод без авторизации" "" \
  "SELECT transfer('aaaa1111-1111-1111-1111-111111111111','aaaa2222-2222-2222-2222-222222222222',100,100)"
check "неудачные попытки не сдвинули баланс" "90000" \
  "$(as_user "$U1" "SELECT balance FROM accounts WHERE id='aaaa1111-1111-1111-1111-111111111111'")"

echo
if (( failures > 0 )); then
  echo "ПРОВАЛЕНО: $failures проверок" >&2
  exit 1
fi
echo "Все проверки схемы прошли"
