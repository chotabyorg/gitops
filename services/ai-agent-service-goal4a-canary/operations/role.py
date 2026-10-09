"""Finite Goal4A PostgreSQL principal lifecycle. No application migrations/data writes.

The same file runs in reviewed Jobs and readonly startup verification. Release
inputs are fixed nonsecret JSON; credentials are individual environment keyRefs.
All outward diagnostics are fixed codes. Never print SQL or driver exceptions.
"""

import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re

import asyncpg

ROLE = "goal4a_smoke_read"
DATABASE = "ai_agents_db"
HEAD = "bv2_20261008_01"
LOCK = 434853401
SOURCE = "4fa17597b8083d2e09428c9c1ac949aa42f5990d"
IMAGE = "sha256:5eba680cf018acf0f8062bbc1b0909e8c09ff157795e5a7f79ac4232a863ef4c"
OWNER = "dc3dd7eb-536f-45d4-84f2-c8d35575d928"
INTEGRATION = "8d4a1b73-7973-4dcc-a3d4-1312d871c1d4"
AGENT = "0b750714-af8d-4d8c-8fdc-4ddfeda98af9"
FUNCTIONS = (
    "pg_catalog.lo_creat(integer)", "pg_catalog.lo_create(oid)",
    "pg_catalog.lo_from_bytea(oid,bytea)",
    "pg_catalog.pg_logical_emit_message(boolean,text,text,boolean)",
    "pg_catalog.pg_logical_emit_message(boolean,text,bytea,boolean)",
)
COLUMNS = {
    "agent_templates": ("id", "user_id", "name", "system_prompt", "llm_provider",
                        "model_name", "temperature", "is_active", "prompt_config",
                        "timezone", "encrypted_openrouter_key"),
    "business_scopes": ("id", "conversation_id", "owner_id", "agent_owner_id",
                        "agent_id", "integration_id", "channel", "created_at"),
    "alembic_version": ("version_num",),
}
QUIET = {
    "log_statement": "none", "log_duration": "off",
    "log_min_duration_statement": "-1", "log_min_duration_sample": "-1",
    "log_statement_sample_rate": "0", "log_transaction_sample_rate": "0",
    "log_min_error_statement": "panic", "log_parameter_max_length": "0",
    "log_parameter_max_length_on_error": "0", "debug_print_parse": "off",
    "debug_print_rewritten": "off", "debug_print_plan": "off",
}


class GateError(Exception):
    """A bounded public diagnostic, never an SQL/credential-bearing message."""


def require(condition, code):
    if not condition:
        raise GateError(code)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def identifier(value):
    # Identifiers originate in fixed code or the independently frozen inventory.
    require(isinstance(value, str) and re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", value),
            "UNSAFE_IDENTIFIER")
    return '"' + value + '"'


def literal(value):
    # PostgreSQL utility PASSWORD/COMMENT statements do not accept bind args.
    require(isinstance(value, str) and "\x00" not in value, "UNSAFE_LITERAL")
    return "'" + value.replace("'", "''") + "'"


def records(rows):
    return [dict(row) for row in rows]


async def connect(admin=False):
    # No credential-bearing DSN, argv or logging configuration is constructed.
    return await asyncpg.connect(
        host=os.environ["POSTGRES_HOST"], port=int(os.environ.get("POSTGRES_PORT", "5432")),
        database=DATABASE, user="admin" if admin else ROLE,
        password=os.environ["ADMIN_POSTGRES_PASSWORD" if admin else "POSTGRES_PASSWORD"],
        timeout=10, command_timeout=15,
        server_settings={"application_name": "goal4a-role-lifecycle" if admin else "goal4a-readonly-proof",
                         "search_path": "pg_catalog, public",
                         "statement_timeout": "15000", "lock_timeout": "3000",
                         "idle_in_transaction_session_timeout": "15000"},
    )


async def quiet(conn):
    await conn.execute("SET search_path TO pg_catalog, public")
    hooks = await conn.fetch("SELECT name,setting FROM pg_settings WHERE name=ANY($1::text[]) ORDER BY name",
                             ["shared_preload_libraries", "session_preload_libraries", "local_preload_libraries"])
    require(len(hooks) == 3 and all(not row["setting"] for row in hooks), "AUDIT_PRELOAD_PRESENT")
    # Only fixed nonsensitive settings are sent before suppression is verified.
    for key, value in QUIET.items():
        await conn.execute("SELECT pg_catalog.set_config($1,$2,false)", key, value)
    observed = {row["name"]: row["setting"] for row in await conn.fetch(
        "SELECT name,setting FROM pg_settings WHERE name=ANY($1::text[])", list(QUIET))}
    require(observed == QUIET, "SQL_LOG_SUPPRESSION_FAILED")
    await conn.execute("SET standard_conforming_strings=on")
    await conn.execute("SET password_encryption='scram-sha-256'")


async def snapshot(conn):
    """Nonsecret exact catalog inputs; no Agent/config/credential values are read."""
    result = {
        "server_major": int(await conn.fetchval("SHOW server_version_num")) // 10000,
        "database": await conn.fetchval("SELECT current_database()"),
        "heads": await conn.fetch("SELECT version_num FROM public.alembic_version ORDER BY version_num"),
        "databases": await conn.fetch("""SELECT d.oid,d.datname,d.datallowconn,d.datistemplate,
          pg_get_userbyid(d.datdba) AS owner,d.datacl::text AS raw_acl,
          COALESCE((SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END,'grantor',pg_get_userbyid(a.grantor),
            'privilege',a.privilege_type,'grantable',a.is_grantable)
            ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable)
            FROM aclexplode(COALESCE(d.datacl,acldefault('d',d.datdba))) a),'[]'::jsonb)::text AS acl
          FROM pg_database d ORDER BY d.datname"""),
        "functions": await conn.fetch("""SELECT p.oid,p.oid::regprocedure::text AS signature,
          pg_get_userbyid(p.proowner) AS owner,p.proacl::text AS raw_acl,
          (SELECT jsonb_agg(jsonb_build_object('grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC'
            ELSE pg_get_userbyid(a.grantee) END,'grantor',pg_get_userbyid(a.grantor),
            'privilege',a.privilege_type,'grantable',a.is_grantable)
            ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable)
            FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a)::text AS acl
          FROM pg_proc p WHERE p.oid=ANY($1::regprocedure[]::oid[]) ORDER BY p.oid""", list(FUNCTIONS)),
        "login_roles": await conn.fetch("""SELECT rolname,rolsuper,rolinherit,rolcreaterole,
          rolcreatedb,rolcanlogin,rolreplication,rolbypassrls FROM pg_roles
          WHERE rolcanlogin ORDER BY rolname"""),
        "memberships": await conn.fetch("""SELECT pg_get_userbyid(roleid) AS role,
          pg_get_userbyid(member) AS member,admin_option,inherit_option,set_option
          FROM pg_auth_members ORDER BY role,member"""),
        "extensions": await conn.fetch("SELECT extname,extversion FROM pg_extension ORDER BY extname"),
        "large_objects": await conn.fetch("SELECT oid,lomowner,lomacl::text AS acl FROM pg_largeobject_metadata ORDER BY oid"),
        "schema_acl": await conn.fetch("""SELECT n.oid,n.nspname,pg_get_userbyid(n.nspowner) AS owner,
          n.nspacl::text AS raw_acl,COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
          'grantor',pg_get_userbyid(a.grantor),'privilege',a.privilege_type,'grantable',a.is_grantable)
          ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable)
          FROM aclexplode(COALESCE(n.nspacl,acldefault('n',n.nspowner))) a),'[]'::jsonb)::text AS acl
          FROM pg_namespace n WHERE nspname !~ '^pg_' AND nspname<>'information_schema'
          ORDER BY n.nspname"""),
        "public_table_grants": await conn.fetch("""SELECT n.nspname,c.relname,a.privilege_type,a.is_grantable
          FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace,
          LATERAL aclexplode(COALESCE(c.relacl,acldefault(CASE WHEN c.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,c.relowner))) a
          WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND a.grantee=0
          ORDER BY n.nspname,c.relname,a.privilege_type"""),
        "public_definers": await conn.fetch("""SELECT p.oid,p.oid::regprocedure::text AS signature
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
          LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
          WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND p.prosecdef
          AND a.grantee=0 AND a.privilege_type='EXECUTE' ORDER BY p.oid"""),
        "preloads": await conn.fetch("SELECT name,setting FROM pg_settings WHERE name LIKE '%preload_libraries' ORDER BY name"),
    }
    for key, value in list(result.items()):
        if isinstance(value, list):
            result[key] = records(value)
    for key in ("databases", "functions", "schema_acl"):
        for item in result[key]:
            item["acl"] = json.loads(item["acl"])
    return result


def validate_baseline(value):
    require(value["server_major"] == 18 and value["database"] == DATABASE and
            value["heads"] == [{"version_num": HEAD}], "SOURCE_SCHEMA_DRIFT")
    require(value["login_roles"] == [{"rolname": "admin", "rolsuper": True, "rolinherit": True,
            "rolcreaterole": True, "rolcreatedb": True, "rolcanlogin": True,
            "rolreplication": True, "rolbypassrls": True}], "LOGIN_AUTHORITY_DRIFT")
    require([d["datname"] for d in value["databases"]] == [DATABASE, "postgres", "template0", "template1"]
            and all(d["owner"] == "admin" for d in value["databases"]), "DATABASE_IDENTITY_DRIFT")
    require([d["datallowconn"] for d in value["databases"]] == [True, True, False, True], "DATABASE_CONNECTABILITY_DRIFT")
    require(len(value["functions"]) == 5 and {f["oid"] for f in value["functions"]} == {715,957,3457,3577,3578}
            and all(f["owner"] == "admin" for f in value["functions"]), "FUNCTION_IDENTITY_DRIFT")
    require(value["extensions"] == [{"extname": "plpgsql", "extversion": "1.0"}] and
            not value["large_objects"] and not value["public_table_grants"] and
            not value["public_definers"] and all(not p["setting"] for p in value["preloads"]), "UNEXPECTED_WRITE_AUTHORITY")
    expected_members = [{"role": name, "member": "pg_monitor", "admin_option": False,
                         "inherit_option": True, "set_option": True}
                        for name in ("pg_read_all_settings", "pg_read_all_stats", "pg_stat_scan_tables")]
    require(value["memberships"] == expected_members, "ROLE_MEMBERSHIP_DRIFT")


def inputs(path):
    value = json.loads(Path(path).read_text())
    require(value.get("source") == SOURCE and value.get("image") == IMAGE and
            value.get("owner") == OWNER and value.get("integration") == INTEGRATION and
            value.get("agent") == AGENT and value.get("channel") == "WEBSITE_WIDGET",
            "RELEASE_SCOPE_DRIFT")
    require(re.fullmatch(r"goal4a-[a-z0-9-]{1,48}", value.get("release_id", "")), "RELEASE_ID_REQUIRED")
    expiry = datetime.fromisoformat(value["valid_until"])
    require(expiry.tzinfo is not None, "EXPIRY_TIMEZONE_REQUIRED")
    value["valid_until"] = expiry.astimezone(timezone.utc).isoformat()
    validate_baseline(value["baseline"])
    return value


def marker_for(value):
    return {"owner": "goal4a-approved-ai-canary-v2", "release_id": value["release_id"],
            "valid_until": value["valid_until"], "source": SOURCE, "image": IMAGE,
            "scope": [OWNER, INTEGRATION, "WEBSITE_WIDGET", AGENT], "original": value["baseline"]}


async def marker(conn):
    raw = await conn.fetchval("SELECT shobj_description(oid,'pg_authid') FROM pg_roles WHERE rolname=$1", ROLE)
    require(raw is not None and len(raw) < 65536, "UNOWNED_ROLE")
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        raise GateError("UNOWNED_ROLE") from None


def effective(snapshot_value, active=False):
    """Normalize own ACL entries/catalog NULL representation, preserving grantors."""
    value = json.loads(canonical(snapshot_value))
    value["login_roles"] = [r for r in value["login_roles"] if r["rolname"] != ROLE]
    for key in ("databases", "functions"):
        for item in value[key]:
            item.pop("raw_acl", None)
            item["acl"] = [a for a in item["acl"] if a["grantee"] != ROLE]
            if active:
                remove = "EXECUTE" if key == "functions" else (
                    "TEMPORARY" if item["datname"] == DATABASE else "CONNECT" if item["datallowconn"] else None)
                item["acl"] = [a for a in item["acl"] if not (a["grantee"] == "PUBLIC" and a["privilege"] == remove)]
    # Public schema receives only our explicit USAGE; its other ACLs must match.
    for item in value["schema_acl"]:
        item.pop("raw_acl", None)
        item["acl"] = [a for a in item["acl"] if a["grantee"] != ROLE]
    return value


async def no_grant_options(conn):
    require(not await conn.fetchval("""SELECT EXISTS(SELECT 1 FROM (
      SELECT datacl AS acl FROM pg_database UNION ALL SELECT nspacl FROM pg_namespace
      UNION ALL SELECT relacl FROM pg_class UNION ALL SELECT attacl FROM pg_attribute
      UNION ALL SELECT proacl FROM pg_proc) objects,
      LATERAL aclexplode(objects.acl) a WHERE a.grantee=(SELECT oid FROM pg_roles WHERE rolname=$1)
      AND a.is_grantable)""", ROLE), "ROLE_GRANT_OPTION_ESCAPE")


async def verify(conn, value, probes=False):
    require(await conn.fetchval("SELECT current_user") == ROLE, "WRONG_LOGIN")
    require(await conn.fetchval("SHOW transaction_read_only") == "on", "DEFAULT_READONLY_REQUIRED")
    require(await conn.fetchval("SELECT version_num FROM public.alembic_version") == HEAD, "SCHEMA_HEAD_DRIFT")
    require(await marker(conn) == marker_for(value), "OWNERSHIP_MARKER_DRIFT")
    await no_grant_options(conn)
    attrs = dict(await conn.fetchrow("""SELECT rolsuper,rolinherit,rolcreaterole,rolcreatedb,
      rolreplication,rolbypassrls,rolcanlogin,rolconnlimit,rolvaliduntil AS expiry,
      rolconfig FROM pg_roles WHERE rolname=current_user"""))
    require(all(attrs[k] is False for k in ("rolsuper","rolinherit","rolcreaterole","rolcreatedb","rolreplication","rolbypassrls"))
            and attrs["rolcanlogin"] and attrs["rolconnlimit"] == 3, "ROLE_ATTRIBUTES_DRIFT")
    require(attrs["expiry"] == datetime.fromisoformat(value["valid_until"]), "ROLE_EXPIRY_DRIFT")
    require(set(attrs["rolconfig"]) == {"default_transaction_read_only=on", "search_path=pg_catalog, public",
            "statement_timeout=15000", "lock_timeout=3000", "idle_in_transaction_session_timeout=15000"}, "ROLE_SETTINGS_DRIFT")
    require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname=current_user) OR roleid=(SELECT oid FROM pg_roles WHERE rolname=current_user))"), "ROLE_MEMBERSHIP_ESCAPE")
    require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_shdepend WHERE refclassid='pg_authid'::regclass AND refobjid=(SELECT oid FROM pg_roles WHERE rolname=current_user) AND deptype='o')"), "ROLE_OWNERSHIP_ESCAPE")
    databases = await conn.fetch("SELECT datname,datallowconn,has_database_privilege(current_user,oid,'CONNECT') AS connect,has_database_privilege(current_user,oid,'CREATE') AS create,has_database_privilege(current_user,oid,'TEMP') AS temp FROM pg_database")
    require(all(not r["create"] and (r["datname"] != DATABASE or not r["temp"])
                and (not r["datallowconn"] or r["connect"] == (r["datname"] == DATABASE)) for r in databases), "DATABASE_AUTHORITY_ESCAPE")
    require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE has_schema_privilege(current_user,oid,'CREATE'))"), "SCHEMA_CREATE_ESCAPE")
    for function in FUNCTIONS:
        require(not await conn.fetchval("SELECT has_function_privilege(current_user,$1::regprocedure,'EXECUTE')", function), "FUNCTION_WRITE_ESCAPE")
    require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema' AND relkind IN ('r','p','v','m','f') AND has_table_privilege(current_user,c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))"), "TABLE_WRITE_ESCAPE")
    require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_class WHERE relkind='S' AND has_sequence_privilege(current_user,oid,'USAGE,SELECT,UPDATE'))"), "SEQUENCE_ESCAPE")
    selected = await conn.fetch("""SELECT n.nspname,c.relname,a.attname FROM pg_attribute a
      JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
      AND has_column_privilege(current_user,c.oid,a.attnum,'SELECT') ORDER BY c.relname,a.attname""")
    expected = sorted(("public", table, col) for table, cols in COLUMNS.items() for col in cols)
    require(sorted(tuple(r.values()) for r in selected) == expected, "COLUMN_READ_SCOPE_DRIFT")
    require(not await conn.fetchval("""SELECT EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace WHERE a.attnum>0 AND NOT a.attisdropped
      AND n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
      AND has_column_privilege(current_user,c.oid,a.attnum,'INSERT,UPDATE,REFERENCES'))"""), "COLUMN_WRITE_ESCAPE")
    observed = effective(await snapshot(conn))
    expected_catalog = effective(value["baseline"], active=True)
    # PG hides privileged preload GUCs from this intentionally minimal role.
    # Privileged lifecycle + independent native verifier prove that separate gate;
    # do not grant pg_read_all_settings or pretend missing rows prove no hooks.
    observed.pop("preloads")
    expected_catalog.pop("preloads")
    require(observed == expected_catalog, "ACTIVE_CATALOG_DRIFT")
    if probes:
        for readonly in (True, False):
            txn = conn.transaction(readonly=readonly)
            await txn.start()
            if not readonly:
                await conn.execute("SET TRANSACTION READ WRITE")
            rejected = False
            try:
                await conn.execute("UPDATE public.agent_templates SET is_active=is_active WHERE false")
            except (asyncpg.ReadOnlySQLTransactionError, asyncpg.InsufficientPrivilegeError):
                rejected = True
            finally:
                await txn.rollback()
            require(rejected, "ZERO_ROW_UPDATE_NOT_REJECTED")
        for statement in ("CREATE TABLE public.goal4a_forbidden_probe(id integer)",
                          "CREATE TEMP TABLE goal4a_forbidden_probe(id integer)"):
            txn = conn.transaction(readonly=False)
            await txn.start()
            await conn.execute("SET TRANSACTION READ WRITE")
            rejected = False
            try:
                await conn.execute(statement)
            except asyncpg.InsufficientPrivilegeError:
                rejected = True
            finally:
                await txn.rollback()  # Includes any unexpected successful DDL.
            require(rejected, "DDL_NOT_REJECTED")
    return {"status": "PASS_READONLY_ROLE_WITH_SAFE_PROBES" if probes else "PASS_READONLY_STARTUP",
            "role": ROLE, "head": HEAD, "select_columns": sum(map(len, COLUMNS.values())),
            "default_transaction_read_only": True, "irreversible_probes": 0}


async def provision(conn, value):
    await quiet(conn)
    expiry = datetime.fromisoformat(value["valid_until"])
    seconds = (expiry - datetime.now(timezone.utc)).total_seconds()
    require(3600 <= seconds <= 172800, "EXPIRY_OUTSIDE_RELEASE_WINDOW")
    async with conn.transaction():
        await conn.execute("SELECT pg_advisory_xact_lock($1)", LOCK)
        exists = await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=$1)", ROLE)
        if exists:
            require(await marker(conn) == marker_for(value), "UNOWNED_ROLE_OR_RELEASE_DRIFT")
            await no_grant_options(conn)
            require(effective(await snapshot(conn)) == effective(value["baseline"], active=True), "IDEMPOTENT_CATALOG_DRIFT")
            return {"status": "ALREADY_PROVISIONED_NO_ROTATION", "role": ROLE}
        require(await snapshot(conn) == value["baseline"], "BASELINE_DRIFT")
        password = os.environ["POSTGRES_PASSWORD"]
        require(re.fullmatch(r"[A-Za-z0-9_-]{43,128}", password), "PASSWORD_FORMAT")
        await conn.execute(f"CREATE ROLE {identifier(ROLE)} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3 PASSWORD {literal(password)} VALID UNTIL {literal(value['valid_until'])}")
        await conn.execute(f"ALTER ROLE {identifier(ROLE)} SET search_path TO pg_catalog, public")
        for setting, setting_value in {"default_transaction_read_only": "on",
                "statement_timeout": "15000", "lock_timeout": "3000", "idle_in_transaction_session_timeout": "15000"}.items():
            await conn.execute(f"ALTER ROLE {identifier(ROLE)} SET {setting} TO {literal(setting_value)}")
        await conn.execute(f"REVOKE TEMPORARY ON DATABASE {identifier(DATABASE)} FROM PUBLIC")
        for database in value["baseline"]["databases"]:
            if database["datallowconn"] and database["datname"] != DATABASE:
                await conn.execute(f"REVOKE CONNECT ON DATABASE {identifier(database['datname'])} FROM PUBLIC")
        for function in FUNCTIONS:
            await conn.execute(f"REVOKE EXECUTE ON FUNCTION {function} FROM PUBLIC")
        await conn.execute(f"GRANT CONNECT ON DATABASE {identifier(DATABASE)} TO {identifier(ROLE)}")
        await conn.execute(f"GRANT USAGE ON SCHEMA public TO {identifier(ROLE)}")
        for table, columns in COLUMNS.items():
            await conn.execute(f"GRANT SELECT ({','.join(identifier(c) for c in columns)}) ON TABLE public.{identifier(table)} TO {identifier(ROLE)}")
        await conn.execute(f"COMMENT ON ROLE {identifier(ROLE)} IS {literal(canonical(marker_for(value)))}")
        require(effective(await snapshot(conn)) == effective(value["baseline"], active=True), "PROVISION_POSTCONDITION_DRIFT")
    return {"status": "PROVISIONED_ONCE", "role": ROLE, "expiry": value["valid_until"]}


async def cleanup(conn, value):
    await quiet(conn)
    gate = value.get("cleanup_gate", {})
    require(gate.get("all_work_terminal") is True and gate.get("worker_inactive") is True and
            gate.get("canary_absent") is True and re.fullmatch(r"[0-9a-f]{64}", gate.get("independent_evidence_sha256", "")), "CLEANUP_NATIVE_GATE_REQUIRED")
    async with conn.transaction():
        await conn.execute("SELECT pg_advisory_xact_lock($1)", LOCK)
        exists = await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=$1)", ROLE)
        if not exists:
            require(effective(await snapshot(conn)) == effective(value["baseline"]), "CLEANUP_RESTORATION_DRIFT")
            return {"status": "ALREADY_REMOVED_RESTORATION_VERIFIED", "role": ROLE}
        require(await marker(conn) == marker_for(value), "CLEANUP_OWNERSHIP_DRIFT")
        await no_grant_options(conn)
        require(effective(await snapshot(conn)) == effective(value["baseline"], active=True), "CLEANUP_CATALOG_DRIFT")
        require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE usename=$1)", ROLE), "ROLE_CONNECTIONS_REMAIN")
        require(not await conn.fetchval("SELECT EXISTS(SELECT 1 FROM pg_shdepend WHERE refclassid='pg_authid'::regclass AND refobjid=(SELECT oid FROM pg_roles WHERE rolname=$1) AND deptype NOT IN ('a','i'))", ROLE), "UNEXPECTED_ROLE_DEPENDENCY")
        await conn.execute(f"ALTER ROLE {identifier(ROLE)} NOLOGIN")
        for table, columns in COLUMNS.items():
            await conn.execute(f"REVOKE SELECT ({','.join(identifier(c) for c in columns)}) ON TABLE public.{identifier(table)} FROM {identifier(ROLE)}")
        await conn.execute(f"REVOKE USAGE ON SCHEMA public FROM {identifier(ROLE)}")
        await conn.execute(f"REVOKE CONNECT ON DATABASE {identifier(DATABASE)} FROM {identifier(ROLE)}")
        await conn.execute(f"DROP ROLE {identifier(ROLE)}")
        # Restore ONLY original effective PUBLIC rights removed by this lifecycle.
        for database in value["baseline"]["databases"]:
            privilege = "TEMPORARY" if database["datname"] == DATABASE else "CONNECT" if database["datallowconn"] else None
            original = [a for a in database["acl"] if a["grantee"] == "PUBLIC" and a["privilege"] == privilege]
            if original:
                require(len(original) == 1 and original[0]["grantor"] == "admin" and not original[0]["grantable"], "UNSUPPORTED_ORIGINAL_GRANT")
                await conn.execute(f"GRANT {privilege} ON DATABASE {identifier(database['datname'])} TO PUBLIC")
        for function in value["baseline"]["functions"]:
            original = [a for a in function["acl"] if a["grantee"] == "PUBLIC" and a["privilege"] == "EXECUTE"]
            if original:
                require(len(original) == 1 and original[0]["grantor"] == "admin" and not original[0]["grantable"], "UNSUPPORTED_ORIGINAL_GRANT")
                # Signature/OID already matched the frozen five builtins above.
                await conn.execute(f"GRANT EXECUTE ON FUNCTION pg_catalog.{function['signature']} TO PUBLIC")
        require(effective(await snapshot(conn)) == effective(value["baseline"]), "ACL_RESTORATION_FAILED")
    return {"status": "REMOVED_ORIGINAL_EFFECTIVE_ACLS_RESTORED", "role": ROLE}


async def run(mode, path):
    if mode == "inventory":
        conn = await connect(admin=True)
        try:
            await quiet(conn)
            value = await snapshot(conn)
            validate_baseline(value)
            return {"status": "READONLY_INVENTORY", "baseline": value}
        finally:
            await conn.close()
    value = inputs(path)
    conn = await connect(admin=mode in {"provision", "cleanup"})
    try:
        if mode == "provision":
            result = await provision(conn, value)
        elif mode == "cleanup":
            result = await cleanup(conn, value)
        else:
            return await verify(conn, value, probes=mode == "prove")
    finally:
        await conn.close()
    if mode == "provision":
        # The intended credential must authenticate; idempotence never rotates it.
        readonly = await connect()
        try:
            await verify(readonly, value)
        finally:
            await readonly.close()
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inventory", "provision", "verify", "prove", "cleanup"))
    parser.add_argument("--inputs", default="/operations/release-inputs.json")
    args = parser.parse_args()
    try:
        result = asyncio.run(asyncio.wait_for(run(args.mode, args.inputs), timeout=180))
    except GateError as exc:
        print(canonical({"status": "BLOCKED", "code": str(exc)}), flush=True)
        raise SystemExit(1) from None
    except BaseException:
        print(canonical({"status": "BLOCKED", "code": "LIFECYCLE_FAILURE_NO_PRIVATE_DIAGNOSTICS"}), flush=True)
        raise SystemExit(1) from None
    print(canonical(result), flush=True)


if __name__ == "__main__":
    main()
