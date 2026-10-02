"""Focused real PG18 startup/backup proof; no production, host ports or dumps.

Uses an internal Docker network, a delayed disposable database, separate volumes,
the exact production scripts and UID70/read-only/resource-limited clients.
Removes only unique verifier-owned resources, including synthetic archives.
"""
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

PROD = Path(__file__).resolve().parents[1] / 'prod'
PG = 'postgres:18.6-alpine3.24@sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873'
prefix = 'crm-backup-readiness-' + uuid.uuid4().hex[:8]
containers, volumes = [], []
network_created = False


def run(args, check=True, timeout=60):
    result = subprocess.run(['docker', *args], capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'Docker {args[0]} failed: {result.stderr[:1000]}')
    return result


def start(suffix, args):
    name = prefix + '-' + suffix
    containers.append(name)
    run(['run', '-d', '--name', name, *args])
    return name


def client(volume, network, host='source', database='crm_test', readonly=False):
    return [
        '--network', network, '--read-only', '--user', '70:70', '--cap-drop=ALL',
        '--security-opt=no-new-privileges', '--memory', '128m', '--cpus', '0.25',
        '--tmpfs', '/tmp:uid=70,gid=70,size=33554432',
        '--mount', f'type=volume,src={volume},dst=/backups' + (',readonly' if readonly else ''),
        '--mount', f'type=bind,src={PROD},dst=/opt/crm-backup,readonly',
        '-e', f'PGHOST={host}', '-e', 'PGPORT=5432', '-e', 'PGUSER=crm_test',
        '-e', f'PGDATABASE={database}', '-e', 'BACKUP_DIR=/backups',
        '-e', 'PGCONNECT_TIMEOUT=10',
        '-e', 'PGOPTIONS=-c statement_timeout=600000 -c lock_timeout=30000',
    ]


def files(volume):
    result = run(['run', '--rm', '--network', 'none', '--read-only', '--user', '70:70',
                  '--cap-drop=ALL', '--security-opt=no-new-privileges',
                  '--mount', f'type=volume,src={volume},dst=/backups,readonly',
                  PG, 'find', '/backups', '-mindepth', '1', '-maxdepth', '1', '-type', 'f'])
    return result.stdout.splitlines()


def finish(name, expected):
    code = int(run(['wait', name], timeout=200).stdout.strip())
    assert code == expected, f'{name} returned {code}, expected {expected}'
    logs = run(['logs', name])
    return logs.stdout + logs.stderr


try:
    run(['network', 'create', '--internal', prefix])
    network_created = True
    for suffix in ('source', 'backups', 'never-ready'):
        volume = prefix + '-' + suffix
        run(['volume', 'create', volume])
        volumes.append(volume)
        run(['run', '--rm', '--network', 'none', '--user', '0', '--cap-drop=ALL',
             '--cap-add=CHOWN', '--security-opt=no-new-privileges',
             '--mount', f'type=volume,src={volume},dst=/volume', PG, 'chown', '70:70', '/volume'])

    # Confirm the actual BusyBox utility bounds even a probe that ignores TERM.
    started = time.monotonic()
    # Match the wrapper's shell-parent context; container PID1 signal handling
    # would not represent a timeout subprocess launched by backup-ready.sh.
    timeout_probe = start('probe-timeout', [
        '--network', 'none', '--read-only', '--user', '70:70', '--cap-drop=ALL',
        '--security-opt=no-new-privileges', PG, 'sh', '-c',
        '''timeout -k 1 3 sh -c 'trap "" TERM; while :; do sleep 1; done'; result=$?; exit "$result"''',
    ])
    timeout_code = int(run(['wait', timeout_probe], timeout=12).stdout.strip())
    assert timeout_code != 0 and time.monotonic() - started < 12
    print('PASS pinned BusyBox timeout kills an unresponsive probe', flush=True)

    never_started = time.monotonic()
    never = start('never', [*client(volumes[2], 'none', host='127.0.0.1'),
                            PG, 'sh', '/opt/crm-backup/backup-ready.sh'])

    with tempfile.TemporaryDirectory(prefix=prefix) as fixture_dir:
        fixture = Path(fixture_dir)
        fixture.chmod(0o755)
        (fixture / 'fixture.sql').write_text(
            'CREATE TABLE backup_readiness_probe (id integer PRIMARY KEY);\n'
            'INSERT INTO backup_readiness_probe VALUES (1);\n')
        (fixture / 'fixture.sql').chmod(0o444)
        source = start('source', [
            '--network', prefix, '--network-alias', 'source', '--read-only', '--user', '70:70',
            '--cap-drop=ALL', '--security-opt=no-new-privileges', '--memory', '384m', '--cpus', '0.5',
            '--tmpfs', '/var/run/postgresql:uid=70,gid=70,size=16777216',
            '--tmpfs', '/tmp:uid=70,gid=70,size=67108864',
            '--mount', f'type=volume,src={volumes[0]},dst=/var/lib/postgresql',
            '--mount', f'type=bind,src={fixture},dst=/docker-entrypoint-initdb.d,readonly',
            '-e', 'POSTGRES_USER=crm_test', '-e', 'POSTGRES_DB=crm_test',
            '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', '--entrypoint', 'sh', PG, '-c',
            'sleep 15; exec docker-entrypoint.sh postgres -c shared_buffers=64MB -c max_connections=30',
        ])
        assert run(['exec', source, 'pg_isready', '-h', '127.0.0.1', '-t', '2'], check=False).returncode == 2
        delayed = start('delayed', [*client(volumes[1], prefix), PG, 'sh', '/opt/crm-backup/backup-ready.sh'])
        time.sleep(2)
        assert run(['inspect', '--format', '{{.State.Running}}', delayed]).stdout.strip() == 'true'
        assert 'CRM backup waiting for database readiness' in run(['logs', delayed]).stdout
        assert files(volumes[1]) == [], 'Archive appeared before PostgreSQL was available'
        logs = finish(delayed, 0)
        assert logs.count('CRM backup completed') == 1
        assert logs.count('CRM backup database ready') == 1
        archives = files(volumes[1])
        assert len(archives) == 1 and archives[0].endswith('.dump')
        check = run(['run', '--rm', *client(volumes[1], 'none', readonly=True), PG, 'sh', '-c',
                     'set -- /backups/chotacrm-*.dump; test "$#" -eq 1; '
                     'test "$(stat -c %a "$1")" = 600; pg_restore --list "$1"'])
        assert 'TABLE DATA public backup_readiness_probe' in check.stdout
        print('PASS initially unavailable real PG18 becomes ready; one valid mode0600 archive on separate volume', flush=True)

        # pg_isready accepts a server with an invalid database name. The real
        # pg_dump error must remain a nonzero backup failure, with no retry.
        bad_db = start('bad-db', [*client(volumes[1], prefix, database='missing_test_database'),
                                  PG, 'sh', '/opt/crm-backup/backup-ready.sh'])
        logs = finish(bad_db, 1)
        assert 'CRM backup database ready' in logs and 'CRM backup completed' not in logs
        assert files(volumes[1]) == archives
        print('PASS real pg_dump failure propagates; prior archive preserved; no partial or false completion', flush=True)

        readonly = start('readonly', [*client(volumes[1], prefix, readonly=True),
                                      PG, 'sh', '/opt/crm-backup/backup-ready.sh'])
        logs = finish(readonly, 1)
        assert 'CRM backup database ready' in logs and 'CRM backup completed' not in logs
        assert files(volumes[1]) == archives
        print('PASS read-only backup volume fails without false completion or archive changes', flush=True)

        logs = finish(never, 1)
        assert time.monotonic() - never_started < 195
        assert 'CRM backup database readiness timed out' in logs and 'CRM backup completed' not in logs
        assert files(volumes[2]) == []
        print('PASS never-ready real endpoint fails within the bounded budget; no archive created', flush=True)
finally:
    failures = []
    for name in reversed(containers):
        if run(['rm', '-f', name], check=False).returncode:
            failures.append(name)
    for name in volumes:
        if run(['volume', 'rm', name], check=False).returncode:
            failures.append(name)
    if network_created and run(['network', 'rm', prefix], check=False).returncode:
        failures.append(prefix)
    if failures:
        raise RuntimeError('Verifier resource cleanup failed: ' + ', '.join(failures))
    print('PASS removed verifier-owned containers, all three volumes/archives and internal network', flush=True)
