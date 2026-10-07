-- Beaver v2 schema: accounts, planned operations, scenarios, exchange rates and
-- per-user settings.
--
-- The database is shared with the priority-lists app, so every object here is
-- prefixed or named so it cannot collide with `nodes`, `priority_lists` or
-- `priority_items`. The whole file is idempotent: re-running it is a no-op.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Shared updated_at trigger
-- ---------------------------------------------------------------------------

-- Named after the app so it cannot clash with a trigger function of the same
-- purpose belonging to another schema in this database.
CREATE OR REPLACE FUNCTION beaver_touch_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- user_settings — exactly one row per user
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Currency every total is reported in. The app keeps it inside the set of
  -- currencies of the user's non-archived accounts; the database only checks shape.
  base_currency VARCHAR(3) NOT NULL DEFAULT 'RUB'
    CHECK (base_currency ~ '^[A-Z]{3}$'),
  -- Forecast horizon the user last picked. Stored so it survives a restart and
  -- so the home screen and the forecast screen cannot disagree about it.
  forecast_preset TEXT NOT NULL DEFAULT 'plus30' CHECK (forecast_preset IN (
    'end_of_month', 'plus30', 'plus90', 'custom'
  )),
  -- Only meaningful for forecast_preset = 'custom'.
  forecast_custom_date DATE,
  -- Direction of the by-amount sort of the accounts and of the operations on
  -- the home screen. Stored so it follows the user to another device.
  accounts_sort TEXT NOT NULL DEFAULT 'desc'
    CHECK (accounts_sort IN ('asc', 'desc')),
  ops_sort TEXT NOT NULL DEFAULT 'desc' CHECK (ops_sort IN ('asc', 'desc')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- `CREATE TABLE IF NOT EXISTS` above is a no-op on an already deployed database,
-- so the horizon and sort columns are added separately for it.
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS forecast_preset TEXT NOT NULL DEFAULT 'plus30';
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS forecast_custom_date DATE;
ALTER TABLE user_settings
  DROP CONSTRAINT IF EXISTS user_settings_forecast_preset_check;
ALTER TABLE user_settings
  ADD CONSTRAINT user_settings_forecast_preset_check CHECK (forecast_preset IN (
    'end_of_month', 'plus30', 'plus90', 'custom'
  ));
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS accounts_sort TEXT NOT NULL DEFAULT 'desc';
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS ops_sort TEXT NOT NULL DEFAULT 'desc';
ALTER TABLE user_settings
  DROP CONSTRAINT IF EXISTS user_settings_accounts_sort_check;
ALTER TABLE user_settings
  ADD CONSTRAINT user_settings_accounts_sort_check
    CHECK (accounts_sort IN ('asc', 'desc'));
ALTER TABLE user_settings DROP CONSTRAINT IF EXISTS user_settings_ops_sort_check;
ALTER TABLE user_settings
  ADD CONSTRAINT user_settings_ops_sort_check CHECK (ops_sort IN ('asc', 'desc'));

-- Redundant next to the primary key, but kept so every table in this migration
-- is indexed by user_id the same way.
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);

DROP TRIGGER IF EXISTS user_settings_touch_updated_at ON user_settings;
CREATE TRIGGER user_settings_touch_updated_at
  BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION beaver_touch_updated_at();

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own settings" ON user_settings;
CREATE POLICY "Users can view own settings"
  ON user_settings FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own settings" ON user_settings;
CREATE POLICY "Users can insert own settings"
  ON user_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own settings" ON user_settings;
CREATE POLICY "Users can update own settings"
  ON user_settings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own settings" ON user_settings;
CREATE POLICY "Users can delete own settings"
  ON user_settings FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL CHECK (char_length(trim(name)) > 0),
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  -- Minor units (kopecks/cents). BIGINT, not NUMERIC: money is integral here.
  -- May be negative — a card can be overdrawn.
  balance BIGINT NOT NULL DEFAULT 0,
  archived BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_user_order ON accounts(user_id, sort_order);

DROP TRIGGER IF EXISTS accounts_touch_updated_at ON accounts;
CREATE TRIGGER accounts_touch_updated_at
  BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION beaver_touch_updated_at();

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own accounts" ON accounts;
CREATE POLICY "Users can view own accounts"
  ON accounts FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own accounts" ON accounts;
CREATE POLICY "Users can insert own accounts"
  ON accounts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own accounts" ON accounts;
CREATE POLICY "Users can update own accounts"
  ON accounts FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own accounts" ON accounts;
CREATE POLICY "Users can delete own accounts"
  ON accounts FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- planned_ops
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS planned_ops (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL CHECK (char_length(trim(title)) > 0),
  -- Strictly positive: the direction lives in `kind`, never in the sign.
  amount BIGINT NOT NULL CHECK (amount > 0),
  currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
  kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
  category TEXT NOT NULL DEFAULT 'other' CHECK (category IN (
    'food', 'shopping', 'services', 'housing', 'utilities', 'health',
    'education', 'software', 'travel', 'fun', 'debt', 'personal_debt',
    'alimony', 'taxes', 'salary', 'other'
  )),
  -- NULL means "not tied to a particular account": it still moves the total.
  -- Deleting the account only detaches the operation, it does not remove it.
  account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
  schedule TEXT NOT NULL CHECK (schedule IN (
    'once', 'daily', 'weekly', 'biweekly', 'monthly', 'yearly'
  )),
  start_date DATE NOT NULL,
  end_date DATE,
  enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT planned_ops_dates_ordered
    CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Same reason as the user_settings ALTERs above: the CHECKs in the CREATE TABLE
-- never reach a database that already has the table, so the two closed sets are
-- restated here. Postgres names an inline column CHECK `<table>_<column>_check`.
ALTER TABLE planned_ops DROP CONSTRAINT IF EXISTS planned_ops_category_check;
ALTER TABLE planned_ops ADD CONSTRAINT planned_ops_category_check CHECK (
  category IN (
    'food', 'shopping', 'services', 'housing', 'utilities', 'health',
    'education', 'software', 'travel', 'fun', 'debt', 'personal_debt',
    'alimony', 'taxes', 'salary', 'other'
  )
);
ALTER TABLE planned_ops DROP CONSTRAINT IF EXISTS planned_ops_schedule_check;
ALTER TABLE planned_ops ADD CONSTRAINT planned_ops_schedule_check CHECK (
  schedule IN ('once', 'daily', 'weekly', 'biweekly', 'monthly', 'yearly')
);

CREATE INDEX IF NOT EXISTS idx_planned_ops_user_id ON planned_ops(user_id);
CREATE INDEX IF NOT EXISTS idx_planned_ops_account_id ON planned_ops(account_id);

DROP TRIGGER IF EXISTS planned_ops_touch_updated_at ON planned_ops;
CREATE TRIGGER planned_ops_touch_updated_at
  BEFORE UPDATE ON planned_ops
  FOR EACH ROW EXECUTE FUNCTION beaver_touch_updated_at();

ALTER TABLE planned_ops ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own planned ops" ON planned_ops;
CREATE POLICY "Users can view own planned ops"
  ON planned_ops FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own planned ops" ON planned_ops;
CREATE POLICY "Users can insert own planned ops"
  ON planned_ops FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own planned ops" ON planned_ops;
CREATE POLICY "Users can update own planned ops"
  ON planned_ops FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own planned ops" ON planned_ops;
CREATE POLICY "Users can delete own planned ops"
  ON planned_ops FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- scenarios
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS scenarios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL CHECK (char_length(trim(name)) > 0),
  -- The built-in «Все» scenario. The app forbids deleting it.
  is_default BOOLEAN NOT NULL DEFAULT false,
  -- Exclusions, not inclusions: anything created later is automatically part of
  -- every scenario, which is why these are plain id arrays and not join tables.
  disabled_account_ids UUID[] NOT NULL DEFAULT '{}',
  disabled_op_ids UUID[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scenarios_user_id ON scenarios(user_id);

-- At most one default scenario per user.
CREATE UNIQUE INDEX IF NOT EXISTS idx_scenarios_one_default
  ON scenarios(user_id) WHERE is_default;

DROP TRIGGER IF EXISTS scenarios_touch_updated_at ON scenarios;
CREATE TRIGGER scenarios_touch_updated_at
  BEFORE UPDATE ON scenarios
  FOR EACH ROW EXECUTE FUNCTION beaver_touch_updated_at();

ALTER TABLE scenarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own scenarios" ON scenarios;
CREATE POLICY "Users can view own scenarios"
  ON scenarios FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own scenarios" ON scenarios;
CREATE POLICY "Users can insert own scenarios"
  ON scenarios FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own scenarios" ON scenarios;
CREATE POLICY "Users can update own scenarios"
  ON scenarios FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own scenarios" ON scenarios;
CREATE POLICY "Users can delete own scenarios"
  ON scenarios FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- rates
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code VARCHAR(3) NOT NULL CHECK (code ~ '^[A-Z]{3}$'),
  -- How many units of `code` one USD buys. The only floating-point number in the
  -- schema; money is always integral.
  rate_per_usd DOUBLE PRECISION NOT NULL CHECK (rate_per_usd > 0),
  -- 'auto' rows are refreshed from the rate API; 'manual' rows are the user's
  -- own override and the refresh must skip them. Resetting an override means
  -- deleting the row so the next refresh can recreate it.
  source TEXT NOT NULL DEFAULT 'auto' CHECK (source IN ('auto', 'manual')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One row per currency per user, so the client's upsert can target it.
  CONSTRAINT rates_user_code_unique UNIQUE (user_id, code)
);

CREATE INDEX IF NOT EXISTS idx_rates_user_id ON rates(user_id);

DROP TRIGGER IF EXISTS rates_touch_updated_at ON rates;
CREATE TRIGGER rates_touch_updated_at
  BEFORE UPDATE ON rates
  FOR EACH ROW EXECUTE FUNCTION beaver_touch_updated_at();

ALTER TABLE rates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own rates" ON rates;
CREATE POLICY "Users can view own rates"
  ON rates FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own rates" ON rates;
CREATE POLICY "Users can insert own rates"
  ON rates FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own rates" ON rates;
CREATE POLICY "Users can update own rates"
  ON rates FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own rates" ON rates;
CREATE POLICY "Users can delete own rates"
  ON rates FOR DELETE
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- transfer(): move money between two of the caller's accounts
-- ---------------------------------------------------------------------------

-- Two amounts, not one: a cross-currency transfer carries its own rate, and the
-- user may round the credited side by hand.
--
-- SECURITY INVOKER, so RLS still applies and the function cannot be used to
-- reach another user's rows. The explicit ownership check is what turns an
-- RLS-filtered no-op UPDATE into a loud error instead of a silent success.
CREATE OR REPLACE FUNCTION transfer(
  from_id UUID,
  to_id UUID,
  from_amount BIGINT,
  to_amount BIGINT
) RETURNS void AS $$
DECLARE
  caller UUID := auth.uid();
  from_owner UUID;
  to_owner UUID;
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'transfer requires an authenticated user';
  END IF;

  IF from_id = to_id THEN
    RAISE EXCEPTION 'cannot transfer to the same account';
  END IF;

  IF from_amount <= 0 OR to_amount <= 0 THEN
    RAISE EXCEPTION 'transfer amounts must be positive';
  END IF;

  -- Lock both rows in a stable order so two concurrent transfers between the
  -- same pair of accounts cannot deadlock.
  IF from_id < to_id THEN
    SELECT user_id INTO from_owner FROM accounts WHERE id = from_id FOR UPDATE;
    SELECT user_id INTO to_owner FROM accounts WHERE id = to_id FOR UPDATE;
  ELSE
    SELECT user_id INTO to_owner FROM accounts WHERE id = to_id FOR UPDATE;
    SELECT user_id INTO from_owner FROM accounts WHERE id = from_id FOR UPDATE;
  END IF;

  IF from_owner IS NULL OR from_owner <> caller THEN
    RAISE EXCEPTION 'source account % is not available', from_id;
  END IF;
  IF to_owner IS NULL OR to_owner <> caller THEN
    RAISE EXCEPTION 'destination account % is not available', to_id;
  END IF;

  UPDATE accounts SET balance = balance - from_amount WHERE id = from_id;
  UPDATE accounts SET balance = balance + to_amount WHERE id = to_id;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- PostgREST needs an explicit grant to expose the RPC.
GRANT EXECUTE ON FUNCTION transfer(UUID, UUID, BIGINT, BIGINT) TO authenticated;
