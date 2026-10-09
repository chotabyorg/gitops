"""Focused real PostgreSQL 18 tests on one explicitly owned disposable container."""

import asyncio
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import unittest
import uuid

import asyncpg

spec = importlib.util.spec_from_file_location("goal4a_role", Path(__file__).with_name("role.py"))
role = importlib.util.module_from_spec(spec)
spec.loader.exec_module(role)


def docker(*args, check=True, env=None):
    result = subprocess.run(["docker", *args], capture_output=True, text=True, env=env)
    if check and result.returncode:
        raise RuntimeError("OWNED_TEST_CONTAINER_COMMAND_FAILED")
    return result.stdout + result.stderr if args and args[0] == "logs" else result.stdout


class RoleLifecycle(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        cls.name = "goal4a-role-test-" + uuid.uuid4().hex[:12]
        cls.admin_password = secrets.token_urlsafe(36)
        cls.password = "goal4a_synthetic_secret_" + secrets.token_urlsafe(36)
        cls.saved_env = {k: os.environ.get(k) for k in
                         ("POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_PASSWORD", "ADMIN_POSTGRES_PASSWORD")}
        env = dict(os.environ, POSTGRES_PASSWORD=cls.admin_password)
        cls.container = docker("run", "--rm", "-d", "--name", cls.name,
            "--label", "goal4a.test.owner=" + cls.name, "--env", "POSTGRES_PASSWORD",
            "--env", "POSTGRES_USER=admin", "--env", "POSTGRES_DB=ai_agents_db",
            "-p", "127.0.0.1::5432", "postgres:18-alpine", env=env).strip()
        port = json.loads(docker("inspect", cls.container))[0]["NetworkSettings"]["Ports"]["5432/tcp"][0]["HostPort"]
        os.environ.update(POSTGRES_HOST="127.0.0.1", POSTGRES_PORT=port,
                          ADMIN_POSTGRES_PASSWORD=cls.admin_password, POSTGRES_PASSWORD=cls.password)

    @classmethod
    def tearDownClass(cls):
        logs = docker("logs", cls.container, check=False)
        cls.secret_log_matches = logs.count(cls.password) + logs.count(cls.admin_password)
        docker("rm", "-f", cls.container, check=False)
        for key, value in cls.saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        if cls.secret_log_matches:
            raise AssertionError("SYNTHETIC_SECRET_REACHED_POSTGRES_LOG")

    async def asyncSetUp(self):
        self.admin = None
        for _ in range(60):
            try:
                self.admin = await role.connect(admin=True)
                break
            except (OSError, asyncpg.CannotConnectNowError):
                await asyncio.sleep(.2)
        self.assertIsNotNone(self.admin)
        await role.quiet(self.admin)
        await self.admin.execute("DROP TABLE IF EXISTS public.agent_templates,public.business_scopes,public.alembic_version")
        await self.admin.execute("CREATE TABLE public.agent_templates(id uuid,user_id uuid,name text,system_prompt text,llm_provider text,model_name text,temperature text,is_active boolean,prompt_config text,timezone text,encrypted_openrouter_key text,forbidden_private_column text)")
        await self.admin.execute("CREATE TABLE public.business_scopes(id uuid,conversation_id uuid,owner_id uuid,agent_owner_id uuid,agent_id uuid,integration_id uuid,channel text,created_at timestamptz)")
        await self.admin.execute("CREATE TABLE public.alembic_version(version_num text NOT NULL)")
        await self.admin.execute("INSERT INTO public.alembic_version VALUES($1)", role.HEAD)
        await self.admin.execute("INSERT INTO public.agent_templates(id,is_active,forbidden_private_column) VALUES($1,true,'synthetic-private')", uuid.uuid4())
        self.baseline = await role.snapshot(self.admin)
        role.validate_baseline(self.baseline)
        self.value = {"source": role.SOURCE, "image": role.IMAGE, "owner": role.OWNER,
                      "integration": role.INTEGRATION, "agent": role.AGENT,
                      "channel": "WEBSITE_WIDGET", "release_id": "goal4a-test-v1",
                      "valid_until": (datetime.now(timezone.utc)+timedelta(hours=24)).isoformat(),
                      "baseline": self.baseline,
                      "cleanup_gate": {"all_work_terminal": True, "worker_inactive": True,
                                       "canary_absent": True, "independent_evidence_sha256": "a"*64}}
        self.row_before = await self.admin.fetchval("SELECT md5(row_to_json(t)::text) FROM public.agent_templates t")

    async def asyncTearDown(self):
        if await self.admin.fetchval("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=$1)", role.ROLE):
            await role.cleanup(self.admin, self.value)
        self.assertEqual(self.row_before, await self.admin.fetchval("SELECT md5(row_to_json(t)::text) FROM public.agent_templates t"))
        await self.admin.close()

    async def test_original_escapes_then_corrected_role_and_restoration(self):
        # All original irreversible/WAL demonstrations are DISPOSABLE ONLY.
        await self.admin.execute("CREATE ROLE unsafe_goal4a_test LOGIN PASSWORD 'synthetic-disposable-only'")
        unsafe = await asyncpg.connect(host=os.environ["POSTGRES_HOST"], port=int(os.environ["POSTGRES_PORT"]),
            database=role.DATABASE, user="unsafe_goal4a_test", password="synthetic-disposable-only")
        try:
            await unsafe.execute("CREATE TEMP TABLE original_temp_escape(id integer)")
            oid = await unsafe.fetchval("SELECT pg_catalog.lo_create(0)")
            self.assertTrue(await self.admin.fetchval("SELECT EXISTS(SELECT 1 FROM pg_largeobject_metadata WHERE oid=$1)", oid))
            before = await unsafe.fetchval("SELECT pg_current_wal_insert_lsn()::text")
            emitted = await unsafe.fetchval("SELECT pg_logical_emit_message(false,'goal4a-disposable','synthetic',false)::text")
            self.assertNotEqual(before, emitted)
            other = await asyncpg.connect(host=os.environ["POSTGRES_HOST"], port=int(os.environ["POSTGRES_PORT"]),
                database="postgres", user="unsafe_goal4a_test", password="synthetic-disposable-only")
            await other.close()
            await self.admin.execute("SELECT lo_unlink($1)", oid)
        finally:
            await unsafe.close()
            await self.admin.execute("DROP ROLE unsafe_goal4a_test")
        self.assertEqual(self.baseline, await role.snapshot(self.admin))
        result = await role.provision(self.admin, self.value)
        self.assertEqual(result["status"], "PROVISIONED_ONCE")
        readonly = await role.connect()
        try:
            actual = role.effective(await role.snapshot(readonly))
            expected = role.effective(self.baseline, active=True)
            actual.pop("preloads")
            expected.pop("preloads")
            self.assertFalse([key for key in expected if expected[key] != actual[key]],
                             "READONLY_METADATA_VISIBILITY")
            self.assertEqual((await role.verify(readonly, self.value, probes=True))["status"], "PASS_READONLY_ROLE_WITH_SAFE_PROBES")
            # Default RO can be overridden, but authority remains denied.
            await readonly.execute("SET default_transaction_read_only=off")
            for function in role.FUNCTIONS:
                self.assertFalse(await readonly.fetchval("SELECT has_function_privilege(current_user,$1::regprocedure,'EXECUTE')", function))
            with self.assertRaises(asyncpg.InsufficientPrivilegeError):
                await readonly.fetchval("SELECT pg_catalog.lo_create(0)")
            with self.assertRaises(asyncpg.InsufficientPrivilegeError):
                await readonly.fetchval("SELECT forbidden_private_column FROM public.agent_templates")
        finally:
            await readonly.close()
        with self.assertRaises(asyncpg.InsufficientPrivilegeError):
            await asyncpg.connect(host=os.environ["POSTGRES_HOST"],port=int(os.environ["POSTGRES_PORT"]),
                database="postgres",user=role.ROLE,password=self.password)
        after = await role.cleanup(self.admin,self.value)
        self.assertEqual(after["status"], "REMOVED_ORIGINAL_EFFECTIVE_ACLS_RESTORED")
        self.assertEqual(role.effective(await role.snapshot(self.admin)), role.effective(self.baseline))
        self.assertEqual((await role.cleanup(self.admin,self.value))["status"], "ALREADY_REMOVED_RESTORATION_VERIFIED")

    async def test_idempotence_no_rotation_extension_or_foreign_role(self):
        await role.provision(self.admin,self.value)
        password_hash = await self.admin.fetchval("SELECT rolpassword FROM pg_authid WHERE rolname=$1",role.ROLE)
        self.assertEqual((await role.provision(self.admin,self.value))["status"], "ALREADY_PROVISIONED_NO_ROTATION")
        self.assertEqual(password_hash,await self.admin.fetchval("SELECT rolpassword FROM pg_authid WHERE rolname=$1",role.ROLE))
        changed = dict(self.value, valid_until=(datetime.now(timezone.utc)+timedelta(hours=25)).isoformat())
        with self.assertRaisesRegex(role.GateError,"UNOWNED_ROLE_OR_RELEASE_DRIFT"):
            await role.provision(self.admin,changed)

    async def test_foreign_role_is_never_reset_or_adopted(self):
        await self.admin.execute(f"CREATE ROLE {role.identifier(role.ROLE)} NOLOGIN")
        try:
            with self.assertRaisesRegex(role.GateError,"UNOWNED_ROLE"):
                await role.provision(self.admin,self.value)
            self.assertFalse(await self.admin.fetchval("SELECT rolcanlogin FROM pg_roles WHERE rolname=$1",role.ROLE))
        finally:
            await self.admin.execute(f"DROP ROLE {role.identifier(role.ROLE)}")

    async def test_real_advisory_wait_prevents_lifecycle_overlap(self):
        other=await role.connect(admin=True)
        blocker=self.admin.transaction()
        await blocker.start()
        await self.admin.execute("SELECT pg_advisory_xact_lock($1)",role.LOCK)
        task=asyncio.create_task(role.provision(other,self.value))
        observed=False
        try:
            for _ in range(40):
                observed=await self.admin.fetchval("SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND locktype='advisory' AND NOT granted)",other.get_server_pid())
                if observed:
                    break
                await asyncio.sleep(.025)
            self.assertTrue(observed,"REAL_DATABASE_ADVISORY_WAIT_REQUIRED")
            self.assertFalse(await self.admin.fetchval("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=$1)",role.ROLE))
        finally:
            await blocker.rollback()
            try:
                result=await task
            finally:
                await other.close()
        self.assertEqual(result["status"],"PROVISIONED_ONCE")

    async def test_cli_auth_error_never_exports_driver_exception_or_secret(self):
        await role.provision(self.admin,self.value)
        with tempfile.NamedTemporaryFile(mode="w",suffix=".json") as handle:
            json.dump(self.value,handle);handle.flush()
            env=dict(os.environ,POSTGRES_PASSWORD="synthetic_incorrect_"+secrets.token_urlsafe(36))
            # No DB credential appears in argv; the role is not rotated by resync.
            process=await asyncio.create_subprocess_exec(sys.executable,str(Path(__file__).with_name("role.py")),
                "provision","--inputs",handle.name,env=env,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
            stdout,stderr=await process.communicate()
            self.assertEqual(process.returncode,1)
            self.assertEqual(json.loads(stdout),{"status":"BLOCKED","code":"LIFECYCLE_FAILURE_NO_PRIVATE_DIAGNOSTICS"})
            self.assertEqual(stderr,b"")
            self.assertNotIn(env["POSTGRES_PASSWORD"].encode(),stdout)

    async def test_precondition_and_mid_transaction_failure_are_atomic(self):
        await self.admin.execute("UPDATE public.alembic_version SET version_num='unexpected'")
        with self.assertRaisesRegex(role.GateError,"BASELINE_DRIFT"):
            await role.provision(self.admin,self.value)
        await self.admin.execute("UPDATE public.alembic_version SET version_num=$1",role.HEAD)
        original_columns = role.COLUMNS
        try:
            role.COLUMNS = {**original_columns,"missing_table":("id",)}
            with self.assertRaises(asyncpg.UndefinedTableError):
                await role.provision(self.admin,self.value)
        finally:
            role.COLUMNS = original_columns
        self.assertFalse(await self.admin.fetchval("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=$1)",role.ROLE))
        self.assertEqual(self.baseline,await role.snapshot(self.admin))

    async def test_cleanup_blocks_connections_acl_drift_and_missing_gate(self):
        await role.provision(self.admin,self.value)
        readonly = await role.connect()
        try:
            with self.assertRaisesRegex(role.GateError,"ROLE_CONNECTIONS_REMAIN"):
                await role.cleanup(self.admin,self.value)
        finally:
            await readonly.close()
        with self.assertRaisesRegex(role.GateError,"CLEANUP_NATIVE_GATE_REQUIRED"):
            await role.cleanup(self.admin,{**self.value,"cleanup_gate":{}})
        await self.admin.execute("GRANT EXECUTE ON FUNCTION pg_catalog.lo_create(oid) TO PUBLIC")
        with self.assertRaisesRegex(role.GateError,"CLEANUP_CATALOG_DRIFT"):
            await role.cleanup(self.admin,self.value)
        await self.admin.execute("REVOKE EXECUTE ON FUNCTION pg_catalog.lo_create(oid) FROM PUBLIC")

    async def test_grant_option_drift_is_rejected_before_cleanup(self):
        await role.provision(self.admin,self.value)
        await self.admin.execute(f"GRANT SELECT(id) ON public.agent_templates TO {role.identifier(role.ROLE)} WITH GRANT OPTION")
        try:
            readonly=await role.connect()
            try:
                with self.assertRaisesRegex(role.GateError,"ROLE_GRANT_OPTION_ESCAPE"):
                    await role.verify(readonly,self.value)
            finally:
                await readonly.close()
            with self.assertRaisesRegex(role.GateError,"ROLE_GRANT_OPTION_ESCAPE"):
                await role.cleanup(self.admin,self.value)
        finally:
            await self.admin.execute(f"REVOKE GRANT OPTION FOR SELECT(id) ON public.agent_templates FROM {role.identifier(role.ROLE)}")

    async def test_synthetic_password_hidden_under_all_logging_and_error_channels(self):
        for key,value in {"log_statement":"all","log_duration":"on","log_min_duration_statement":"0",
                "log_min_duration_sample":"0","log_statement_sample_rate":"1","log_transaction_sample_rate":"1",
                "debug_print_parse":"on","debug_print_rewritten":"on","debug_print_plan":"on",
                "log_parameter_max_length":"-1","log_parameter_max_length_on_error":"-1"}.items():
            await self.admin.execute("SELECT set_config($1,$2,false)",key,value)
        await role.provision(self.admin,self.value)
        # A utility error carries the synthetic password in SQL; suppression must hold.
        with self.assertRaises(asyncpg.DuplicateObjectError):
            await self.admin.execute(f"CREATE ROLE {role.identifier(role.ROLE)} PASSWORD {role.literal(self.password)}")
        self.assertNotIn(self.password,docker("logs",self.container,check=False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
