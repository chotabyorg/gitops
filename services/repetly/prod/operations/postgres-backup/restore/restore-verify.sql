-- Aggregate-only verification of an isolated restore target. No rows or PII
-- are emitted; the final column must be the canonical PostgreSQL boolean true.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
SET LOCAL search_path = public, pg_catalog;

WITH
schema_state AS (
  SELECT COUNT(*) AS valid_count
  WHERE to_regnamespace('public') IS NOT NULL
),
expected_tables(table_name) AS (
  VALUES
    ('User'),
    ('Student'),
    ('TutorProfile'),
    ('TelegramLinkToken'),
    ('_prisma_migrations')
),
table_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(class.oid) FILTER (WHERE class.relkind = 'r') AS valid_count
  FROM expected_tables AS expected
  LEFT JOIN pg_class AS class
    ON class.relnamespace = 'public'::regnamespace
    AND class.relname = expected.table_name
),
migration_state AS (
  SELECT
    25 AS expected_count,
    COUNT(*) AS total_count,
    COUNT(*) FILTER (
      WHERE finished_at IS NOT NULL
        AND rolled_back_at IS NULL
        AND applied_steps_count > 0
    ) AS complete_count,
    COUNT(*) FILTER (
      WHERE migration_name = '20260714184000_telegram_active_token_unique_index'
        AND finished_at IS NOT NULL
        AND rolled_back_at IS NULL
        AND applied_steps_count > 0
    ) AS required_migration_count
  FROM public."_prisma_migrations"
),
table_count_state AS (
  SELECT
    41 AS expected_count,
    COUNT(*) AS table_count,
    COUNT(*) FILTER (WHERE reltuples >= 0) AS plausible_count
  FROM pg_class
  WHERE relnamespace = 'public'::regnamespace
    AND relkind = 'r'
),
foreign_key_state AS (
  SELECT
    95 AS expected_count,
    COUNT(*) AS foreign_key_count,
    COUNT(*) FILTER (WHERE convalidated) AS valid_count
  FROM pg_constraint
  WHERE connamespace = 'public'::regnamespace
    AND contype = 'f'
),
index_state AS (
  SELECT
    100 AS minimum_count,
    COUNT(*) FILTER (WHERE index_state.indisvalid AND index_state.indisready) AS ready_valid_count
  FROM pg_index AS index_state
  JOIN pg_class AS index_class ON index_class.oid = index_state.indexrelid
  WHERE index_class.relnamespace = 'public'::regnamespace
),
telegram_schema_state AS (
  SELECT
    7 AS expected_count,
    COUNT(attribute.attname) AS valid_count
  FROM (
    VALUES
      ('User', 'telegramChatId'),
      ('User', 'telegramLinkedAt'),
      ('User', 'telegramConnectionVersion'),
      ('TelegramLinkToken', 'codeHash'),
      ('TelegramLinkToken', 'purpose'),
      ('TelegramLinkToken', 'expiresAt'),
      ('TelegramLinkToken', 'userId')
  ) AS expected(table_name, column_name)
  JOIN pg_class AS class
    ON class.relnamespace = 'public'::regnamespace
    AND class.relname = expected.table_name
  JOIN pg_attribute AS attribute
    ON attribute.attrelid = class.oid
    AND attribute.attname = expected.column_name
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
)
SELECT
  schema_state.valid_count,
  table_state.expected_count,
  table_state.valid_count,
  migration_state.total_count,
  migration_state.complete_count,
  migration_state.required_migration_count,
  table_count_state.table_count,
  table_count_state.plausible_count,
  foreign_key_state.foreign_key_count,
  foreign_key_state.valid_count,
  index_state.ready_valid_count,
  telegram_schema_state.expected_count,
  telegram_schema_state.valid_count,
  (
    schema_state.valid_count = 1
    AND table_state.expected_count = table_state.valid_count
    AND migration_state.total_count = migration_state.expected_count
    AND migration_state.total_count = migration_state.complete_count
    AND migration_state.required_migration_count = 1
    AND table_count_state.table_count = table_count_state.expected_count
    AND table_count_state.table_count = table_count_state.plausible_count
    AND foreign_key_state.foreign_key_count = foreign_key_state.expected_count
    AND foreign_key_state.foreign_key_count = foreign_key_state.valid_count
    AND index_state.ready_valid_count >= index_state.minimum_count
    AND telegram_schema_state.expected_count = telegram_schema_state.valid_count
  ) AS passed
FROM schema_state
CROSS JOIN table_state
CROSS JOIN migration_state
CROSS JOIN table_count_state
CROSS JOIN foreign_key_state
CROSS JOIN index_state
CROSS JOIN telegram_schema_state;
ROLLBACK;
