-- Aggregate-only PostgreSQL 18 verification for the secure Telegram linking release.
-- It returns counts and a final boolean; it never returns identifiers, hashes, or rows.
-- sql-boolean-guard.sh validates and supplies the app_schema psql variable.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
SET LOCAL search_path TO :"app_schema", pg_catalog;

WITH
target_schema AS (
  SELECT :'app_schema'::text AS name
),
session_schema_state AS (
  SELECT
    COUNT(*) FILTER (
      WHERE current_schema() = target_schema.name
        AND to_regnamespace(target_schema.name) IS NOT NULL
    ) AS valid_count
  FROM target_schema
),
expected_migrations(migration_name) AS (
  VALUES
    ('20260714182000_secure_telegram_linking'),
    ('20260714183000_telegram_identity_unique_index'),
    ('20260714184000_telegram_active_token_unique_index')
),
migration_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(m.id) FILTER (
      WHERE m.finished_at IS NOT NULL
        AND m.rolled_back_at IS NULL
        AND m.applied_steps_count > 0
    ) AS valid_count
  FROM expected_migrations AS expected
  LEFT JOIN :"app_schema"."_prisma_migrations" AS m
    ON m.migration_name = expected.migration_name
),
expected_constraints(table_name, constraint_name, constraint_definition) AS (
  VALUES
    (
      'User',
      'User_telegram_link_pair_check',
      $definition$CHECK (("telegramChatId" IS NULL) = ("telegramLinkedAt" IS NULL))$definition$
    ),
    (
      'User',
      'User_telegram_linked_at_check',
      $definition$CHECK ("telegramLinkedAt" IS NULL OR "telegramLinkedAt" >= "createdAt")$definition$
    ),
    (
      'User',
      'User_telegram_chat_id_check',
      $definition$CHECK ("telegramChatId" IS NULL OR
CASE
    WHEN "telegramChatId" ~ '^[1-9][0-9]{0,15}$'::text THEN "telegramChatId"::numeric <= '9007199254740991'::bigint::numeric
    ELSE false
END)$definition$
    ),
    (
      'User',
      'User_telegram_connection_version_check',
      $definition$CHECK ("telegramConnectionVersion" >= 0)$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_hash_check',
      $definition$CHECK ("codeHash" ~ '^[0-9a-f]{64}$'::text)$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_expiry_check',
      $definition$CHECK ("expiresAt" > "createdAt")$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_purpose_version_check',
      $definition$CHECK (purpose = 'LINK'::"TelegramLinkPurpose" AND "expectedConnectionVersion" IS NULL OR purpose = 'RECONNECT'::"TelegramLinkPurpose" AND "expectedConnectionVersion" IS NOT NULL AND "expectedConnectionVersion" >= 0)$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_settlement_check',
      $definition$CHECK ("usedAt" IS NULL AND "revokedAt" IS NULL AND "activeKey" IS NOT NULL AND "activeKey" = "userId" OR "activeKey" IS NULL AND num_nonnulls("usedAt", "revokedAt") = 1)$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_used_at_check',
      $definition$CHECK ("usedAt" IS NULL OR "usedAt" >= "createdAt" AND "usedAt" <= "expiresAt")$definition$
    ),
    (
      'TelegramLinkToken',
      'TelegramLinkToken_revoked_at_check',
      $definition$CHECK ("revokedAt" IS NULL OR "revokedAt" >= "createdAt")$definition$
    )
),
constraint_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(c.oid) FILTER (
      WHERE c.contype = 'c'
        AND c.convalidated
        AND pg_get_constraintdef(c.oid, true) = expected.constraint_definition
    ) AS valid_count
  FROM expected_constraints AS expected
  CROSS JOIN target_schema AS schema
  LEFT JOIN pg_namespace AS table_namespace
    ON table_namespace.nspname = schema.name
  LEFT JOIN pg_class AS table_class
    ON table_class.relnamespace = table_namespace.oid
    AND table_class.relname = expected.table_name
  LEFT JOIN pg_constraint AS c
    ON c.conrelid = table_class.oid
    AND c.conname = expected.constraint_name
),
expected_columns(
  table_name,
  column_name,
  formatted_type,
  is_not_null,
  default_expression
) AS (
  VALUES
    ('User', 'telegramChatId', 'text', false, NULL::text),
    (
      'User',
      'telegramLinkedAt',
      'timestamp(3) without time zone',
      false,
      NULL::text
    ),
    ('User', 'telegramConnectionVersion', 'integer', true, '0'),
    (
      'TelegramLinkToken',
      'purpose',
      '"TelegramLinkPurpose"',
      true,
      $definition$'LINK'::"TelegramLinkPurpose"$definition$
    ),
    (
      'TelegramLinkToken',
      'revokedAt',
      'timestamp(3) without time zone',
      false,
      NULL::text
    ),
    (
      'TelegramLinkToken',
      'expectedConnectionVersion',
      'integer',
      false,
      NULL::text
    ),
    ('TelegramLinkToken', 'activeKey', 'text', false, NULL::text)
),
column_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(attribute.attnum) FILTER (
      WHERE NOT attribute.attisdropped
        AND format_type(attribute.atttypid, attribute.atttypmod)
          = expected.formatted_type
        AND attribute.attnotnull = expected.is_not_null
        AND pg_get_expr(
          attribute_default.adbin,
          attribute_default.adrelid,
          true
        ) IS NOT DISTINCT FROM expected.default_expression
    ) AS valid_count
  FROM expected_columns AS expected
  CROSS JOIN target_schema AS schema
  LEFT JOIN pg_namespace AS table_namespace
    ON table_namespace.nspname = schema.name
  LEFT JOIN pg_class AS table_class
    ON table_class.relnamespace = table_namespace.oid
    AND table_class.relname = expected.table_name
  LEFT JOIN pg_attribute AS attribute
    ON attribute.attrelid = table_class.oid
    AND attribute.attname = expected.column_name
    AND attribute.attnum > 0
  LEFT JOIN pg_attrdef AS attribute_default
    ON attribute_default.adrelid = attribute.attrelid
    AND attribute_default.adnum = attribute.attnum
),
expected_enum(enum_label, enum_sort_order) AS (
  VALUES
    ('LINK', 1::real),
    ('RECONNECT', 2::real)
),
actual_enum AS (
  SELECT enum.enumlabel, enum.enumsortorder
  FROM target_schema AS schema
  JOIN pg_namespace AS type_namespace
    ON type_namespace.nspname = schema.name
  JOIN pg_type AS enum_type
    ON enum_type.typnamespace = type_namespace.oid
    AND enum_type.typname = 'TelegramLinkPurpose'
    AND enum_type.typtype = 'e'
  JOIN pg_enum AS enum
    ON enum.enumtypid = enum_type.oid
),
enum_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(actual.enumlabel) AS valid_count,
    (SELECT COUNT(*) FROM actual_enum) AS actual_count
  FROM expected_enum AS expected
  LEFT JOIN actual_enum AS actual
    ON actual.enumlabel = expected.enum_label
    AND actual.enumsortorder = expected.enum_sort_order
),
expected_indexes(table_name, index_name, column_name) AS (
  VALUES
    ('User', 'User_telegramChatId_key', 'telegramChatId'),
    ('TelegramLinkToken', 'TelegramLinkToken_activeKey_key', 'activeKey'),
    ('TelegramLinkToken', 'TelegramLinkToken_codeHash_key', 'codeHash')
),
index_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(index_class.oid) FILTER (
      WHERE index_info.indisunique
        AND index_info.indisready
        AND index_info.indisvalid
        AND NOT index_info.indnullsnotdistinct
        AND index_info.indnkeyatts = 1
        AND index_info.indnatts = 1
        AND index_info.indpred IS NULL
        AND index_info.indexprs IS NULL
        AND access_method.amname = 'btree'
        AND pg_get_indexdef(index_info.indexrelid, 1, true)
          = format('%I', expected.column_name)
    ) AS valid_count
  FROM expected_indexes AS expected
  CROSS JOIN target_schema AS schema
  LEFT JOIN pg_namespace AS table_namespace
    ON table_namespace.nspname = schema.name
  LEFT JOIN pg_class AS table_class
    ON table_class.relnamespace = table_namespace.oid
    AND table_class.relname = expected.table_name
  LEFT JOIN pg_class AS index_class
    ON index_class.relname = expected.index_name
    AND index_class.relnamespace = table_namespace.oid
  LEFT JOIN pg_index AS index_info
    ON index_info.indexrelid = index_class.oid
    AND index_info.indrelid = table_class.oid
  LEFT JOIN pg_am AS access_method
    ON access_method.oid = index_class.relam
),
plaintext_column_state AS (
  SELECT COUNT(*) AS forbidden_count
  FROM information_schema.columns AS columns
  CROSS JOIN target_schema AS schema
  WHERE columns.table_schema = schema.name
    AND columns.table_name = 'TelegramLinkToken'
    AND lower(columns.column_name) IN ('code', 'token', 'plaintoken', 'linkcode')
),
user_state AS (
  SELECT
    COUNT(*) FILTER (
      WHERE ("telegramChatId" IS NULL) <> ("telegramLinkedAt" IS NULL)
    ) AS inconsistent_link_pair_count,
    COUNT(*) FILTER (
      WHERE "telegramLinkedAt" IS NOT NULL
        AND "telegramLinkedAt" < "createdAt"
    ) AS linked_before_user_created_count,
    COUNT(*) FILTER (
      WHERE "telegramLinkedAt" > CURRENT_TIMESTAMP + INTERVAL '5 minutes'
    ) AS linked_at_beyond_clock_skew_count,
    COUNT(*) FILTER (
      WHERE "telegramConnectionVersion" < 0
    ) AS invalid_connection_version_count,
    COUNT(*) FILTER (
      WHERE "telegramChatId" IS NOT NULL
        AND NOT CASE
          WHEN "telegramChatId" ~ '^[1-9][0-9]{0,15}$'
            THEN "telegramChatId"::numeric <= 9007199254740991
          ELSE FALSE
        END
    ) AS invalid_chat_id_count
  FROM :"app_schema"."User"
),
duplicate_identity_state AS (
  SELECT COUNT(*) AS duplicate_group_count
  FROM (
    SELECT 1
    FROM :"app_schema"."User"
    WHERE "telegramChatId" IS NOT NULL
    GROUP BY "telegramChatId"
    HAVING COUNT(*) > 1
  ) AS duplicate_groups
),
token_state AS (
  SELECT
    COUNT(*) FILTER (WHERE "codeHash" !~ '^[0-9a-f]{64}$') AS invalid_hash_count,
    COUNT(*) FILTER (WHERE "expiresAt" <= "createdAt") AS invalid_expiry_count,
    COUNT(*) FILTER (
      WHERE NOT (
        ("purpose" = 'LINK' AND "expectedConnectionVersion" IS NULL)
        OR
        (
          "purpose" = 'RECONNECT'
          AND "expectedConnectionVersion" IS NOT NULL
          AND "expectedConnectionVersion" >= 0
        )
      )
    ) AS invalid_purpose_count,
    COUNT(*) FILTER (
      WHERE NOT (
        (
          "usedAt" IS NULL
          AND "revokedAt" IS NULL
          AND "activeKey" IS NOT NULL
          AND "activeKey" = "userId"
        )
        OR
        (
          "activeKey" IS NULL
          AND num_nonnulls("usedAt", "revokedAt") = 1
        )
      )
    ) AS invalid_settlement_count,
    COUNT(*) FILTER (
      WHERE "usedAt" IS NOT NULL
        AND ("usedAt" < "createdAt" OR "usedAt" > "expiresAt")
    ) AS invalid_used_at_count,
    COUNT(*) FILTER (
      WHERE "revokedAt" IS NOT NULL AND "revokedAt" < "createdAt"
    ) AS invalid_revoked_at_count
  FROM :"app_schema"."TelegramLinkToken"
),
orphan_state AS (
  SELECT COUNT(*) AS orphan_count
  FROM :"app_schema"."TelegramLinkToken" AS token
  LEFT JOIN :"app_schema"."User" AS owner ON owner.id = token."userId"
  WHERE owner.id IS NULL
)
SELECT
  session_schema_state.valid_count AS valid_session_schema_count,
  migration_state.expected_count AS expected_migration_count,
  migration_state.valid_count AS valid_migration_count,
  constraint_state.expected_count AS expected_constraint_count,
  constraint_state.valid_count AS valid_constraint_count,
  column_state.expected_count AS expected_column_count,
  column_state.valid_count AS valid_column_count,
  enum_state.expected_count AS expected_enum_label_count,
  enum_state.valid_count AS valid_enum_label_count,
  enum_state.actual_count AS actual_enum_label_count,
  index_state.expected_count AS expected_index_count,
  index_state.valid_count AS valid_index_count,
  plaintext_column_state.forbidden_count AS forbidden_plaintext_column_count,
  user_state.inconsistent_link_pair_count,
  user_state.linked_before_user_created_count,
  user_state.linked_at_beyond_clock_skew_count,
  user_state.invalid_connection_version_count,
  user_state.invalid_chat_id_count,
  duplicate_identity_state.duplicate_group_count,
  token_state.invalid_hash_count,
  token_state.invalid_expiry_count,
  token_state.invalid_purpose_count,
  token_state.invalid_settlement_count,
  token_state.invalid_used_at_count,
  token_state.invalid_revoked_at_count,
  orphan_state.orphan_count,
  (
    session_schema_state.valid_count = 1
    AND migration_state.expected_count = 3
    AND migration_state.valid_count = migration_state.expected_count
    AND constraint_state.expected_count = 10
    AND constraint_state.valid_count = constraint_state.expected_count
    AND column_state.expected_count = 7
    AND column_state.valid_count = column_state.expected_count
    AND enum_state.expected_count = 2
    AND enum_state.valid_count = enum_state.expected_count
    AND enum_state.actual_count = enum_state.expected_count
    AND index_state.expected_count = 3
    AND index_state.valid_count = index_state.expected_count
    AND plaintext_column_state.forbidden_count = 0
    AND user_state.inconsistent_link_pair_count = 0
    AND user_state.linked_before_user_created_count = 0
    AND user_state.linked_at_beyond_clock_skew_count = 0
    AND user_state.invalid_connection_version_count = 0
    AND user_state.invalid_chat_id_count = 0
    AND duplicate_identity_state.duplicate_group_count = 0
    AND token_state.invalid_hash_count = 0
    AND token_state.invalid_expiry_count = 0
    AND token_state.invalid_purpose_count = 0
    AND token_state.invalid_settlement_count = 0
    AND token_state.invalid_used_at_count = 0
    AND token_state.invalid_revoked_at_count = 0
    AND orphan_state.orphan_count = 0
  ) AS postflight_passes
FROM session_schema_state,
  migration_state,
  constraint_state,
  column_state,
  enum_state,
  index_state,
  plaintext_column_state,
  user_state,
  duplicate_identity_state,
  token_state,
  orphan_state;

ROLLBACK;
