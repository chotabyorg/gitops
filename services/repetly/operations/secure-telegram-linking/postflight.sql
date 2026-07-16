-- Aggregate-only verification for the secure Telegram linking release.
-- It returns counts and a final boolean; it never returns identifiers, hashes, or rows.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

WITH
target_schema AS (
  SELECT current_schema() AS name
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
  LEFT JOIN "_prisma_migrations" AS m
    ON m.migration_name = expected.migration_name
),
expected_constraints(table_name, constraint_name) AS (
  VALUES
    ('User', 'User_telegram_link_pair_check'),
    ('User', 'User_telegram_linked_at_check'),
    ('User', 'User_telegram_chat_id_check'),
    ('User', 'User_telegram_connection_version_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_hash_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_expiry_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_purpose_version_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_settlement_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_used_at_check'),
    ('TelegramLinkToken', 'TelegramLinkToken_revoked_at_check')
),
constraint_state AS (
  SELECT
    COUNT(*) AS expected_count,
    COUNT(c.oid) FILTER (WHERE c.contype = 'c' AND c.convalidated) AS valid_count
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
  FROM "User"
),
duplicate_identity_state AS (
  SELECT COUNT(*) AS duplicate_group_count
  FROM (
    SELECT 1
    FROM "User"
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
  FROM "TelegramLinkToken"
),
orphan_state AS (
  SELECT COUNT(*) AS orphan_count
  FROM "TelegramLinkToken" AS token
  LEFT JOIN "User" AS owner ON owner.id = token."userId"
  WHERE owner.id IS NULL
)
SELECT
  migration_state.expected_count AS expected_migration_count,
  migration_state.valid_count AS valid_migration_count,
  constraint_state.expected_count AS expected_constraint_count,
  constraint_state.valid_count AS valid_constraint_count,
  index_state.expected_count AS expected_index_count,
  index_state.valid_count AS valid_index_count,
  plaintext_column_state.forbidden_count AS forbidden_plaintext_column_count,
  user_state.inconsistent_link_pair_count,
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
    migration_state.expected_count = 3
    AND migration_state.valid_count = migration_state.expected_count
    AND constraint_state.expected_count = 10
    AND constraint_state.valid_count = constraint_state.expected_count
    AND index_state.expected_count = 3
    AND index_state.valid_count = index_state.expected_count
    AND plaintext_column_state.forbidden_count = 0
    AND user_state.inconsistent_link_pair_count = 0
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
FROM migration_state,
  constraint_state,
  index_state,
  plaintext_column_state,
  user_state,
  duplicate_identity_state,
  token_state,
  orphan_state;

ROLLBACK;
