# Dedicated PostgreSQL backup role

This is a setup contract, not a production execution command. The backup Job
must use `repetly_backup`; it must never receive the application database
identity, which currently has elevated rights.

## Preconditions

- An approved database owner executes `postgres-backup-role.sql` through the
  audited administration path. Do not paste an administration password into a
  terminal transcript, manifest, issue, or this repository.
- Configure the login password through the organisation's secret workflow and
  place it only in the separately provisioned DB credential Secret.
- Confirm the database server offers TLS and provide a server CA so the Job can
  connect with `PGSSLMODE=verify-full`.
- If object ownership is not `repetly`, replace the `ALTER DEFAULT PRIVILEGES
  FOR ROLE repetly` clauses with the actual owner only after review.

## Effective privilege contract

The role is LOGIN, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`,
`NOREPLICATION`, `NOBYPASSRLS`, and `NOINHERIT`. It receives only CONNECT,
schema USAGE, table SELECT, and sequence USAGE/SELECT in `public`; it receives
no password in this SQL and no table or sequence write privilege. PostgreSQL may
still expose the database-wide `TEMPORARY` privilege through its default `PUBLIC`
grant. A role-specific `REVOKE` cannot override that additive grant; removing it
would be a separately reviewed database-wide change and is not hidden here.

Before activation, run a sanitized verification that returns only booleans and
aggregates:

```sql
SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication,
       rolbypassrls, rolinherit
FROM pg_roles WHERE rolname = 'repetly_backup';

SELECT has_database_privilege('repetly_backup', 'repetly', 'CONNECT') AS can_connect,
       has_database_privilege('repetly_backup', 'repetly', 'TEMPORARY') AS effective_temp,
       NOT EXISTS (
         SELECT 1
         FROM pg_database AS database
         CROSS JOIN LATERAL aclexplode(
           COALESCE(database.datacl, acldefault('d', database.datdba))
         ) AS acl
         WHERE database.datname = 'repetly'
           AND acl.grantee = 'repetly_backup'::regrole
           AND acl.privilege_type = 'TEMPORARY'
       ) AS no_direct_temp_grant,
       count(*) FILTER (WHERE has_table_privilege('repetly_backup', c.oid, 'INSERT')
                      OR has_table_privilege('repetly_backup', c.oid, 'UPDATE')
                      OR has_table_privilege('repetly_backup', c.oid, 'DELETE')
                      OR has_table_privilege('repetly_backup', c.oid, 'TRUNCATE')) AS writable_relations
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'f');
```

Expected result: `can_connect=true`, `no_direct_temp_grant=true`, every elevated
role attribute false, and `writable_relations=0`. `effective_temp` may be true
only because of the database-wide `PUBLIC` grant; record that explicitly in the
activation review rather than claiming a role-specific denial.

## Row-level security caveat

`NOBYPASSRLS` is deliberate. PostgreSQL applies row-security policies to a
non-bypassing backup role, so a table with enabled RLS can yield an incomplete
logical backup unless its policy permits this read-only role. Before activation,
test `pg_dump` against a disposable copy or an approved read-only verification
path. Do not solve an RLS failure by granting `BYPASSRLS` or reusing the
application superuser; have the data owner approve a narrow RLS policy or keep
the schedule suspended.
