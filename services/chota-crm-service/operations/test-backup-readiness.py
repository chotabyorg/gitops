"""Fast behavioral regression for the startup guard; no Docker or credentials."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROD = Path(__file__).resolve().parents[1] / 'prod'


class BackupReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='crm-backup-ready-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.backups = self.root / 'backups'
        self.backups.mkdir()
        for name in ('backup-ready.sh', 'backup.sh'):
            shutil.copyfile(PROD / name, self.root / name)
        self.env = {
            **os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
            'TEST_ROOT': str(self.root), 'BACKUP_DIR': str(self.backups),
            'PGHOST': 'test-only', 'PGUSER': 'test-only', 'PGDATABASE': 'test-only',
            'PGPASSWORD': 'synthetic-value-must-not-appear',
            'READY_AFTER': '2', 'DUMP_EXIT': '0', 'RESTORE_EXIT': '0',
        }
        # Preserve timeout's command dispatch, but skip real time in unit tests.
        # The real pinned BusyBox timeout is exercised by verify-backup-readiness.py.
        self.stub('timeout', 'printf "%s\\n" "$*" >> "$TEST_ROOT/timeouts"\nshift 3\nexec "$@"')
        self.stub('sleep', 'printf "%s\\n" "$*" >> "$TEST_ROOT/sleeps"')
        self.stub('pg_isready', '''
echo probe >> "$TEST_ROOT/probes"
echo "$PGPASSWORD" >&2
count=$(wc -l < "$TEST_ROOT/probes")
[ "$count" -gt "$READY_AFTER" ]
''')
        self.stub('pg_dump', '''
echo dump >> "$TEST_ROOT/dumps"
for arg in "$@"; do
  case "$arg" in --file=*) printf 'synthetic archive' > "${arg#--file=}";; esac
done
exit "$DUMP_EXIT"
''')
        self.stub('pg_restore', 'exit "$RESTORE_EXIT"')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\nset -eu\n' + body + '\n')
        path.chmod(0o755)

    def run_backup(self):
        result = subprocess.run(['sh', str(self.root / 'backup-ready.sh')], env=self.env,
                                text=True, capture_output=True, timeout=5)
        self.assertNotIn(self.env['PGPASSWORD'], result.stdout + result.stderr)
        return result

    def calls(self, name):
        path = self.root / name
        return path.read_text().splitlines() if path.exists() else []

    def test_initial_refusals_then_ready_run_exactly_one_backup(self):
        result = self.run_backup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls('probes')), 3)
        self.assertEqual(len(self.calls('dumps')), 1)
        self.assertEqual(self.calls('sleeps'), ['2', '2'])
        self.assertEqual(set(self.calls('timeouts')), {'-k 1 3 pg_isready -q -t 2'})
        self.assertEqual(result.stdout.count('CRM backup completed'), 1)
        self.assertEqual(len(list(self.backups.glob('chotacrm-*.dump'))), 1)
        self.assertEqual(list(self.backups.glob('.chotacrm-partial.*')), [])

    def test_never_ready_exhausts_budget_without_starting_dump(self):
        self.env['READY_AFTER'] = '999'
        result = self.run_backup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls('probes')), 30)
        self.assertEqual(len(self.calls('sleeps')), 29)
        self.assertEqual(self.calls('dumps'), [])
        self.assertEqual(list(self.backups.iterdir()), [])
        self.assertIn('CRM backup database readiness timed out', result.stderr)
        self.assertNotIn('CRM backup completed', result.stdout)

    def test_dump_failure_is_not_retried_or_reported_as_complete(self):
        self.env.update(READY_AFTER='0', DUMP_EXIT='49')
        result = self.run_backup()
        self.assertEqual(result.returncode, 49)
        self.assertEqual(len(self.calls('dumps')), 1)
        self.assertEqual(list(self.backups.iterdir()), [])
        self.assertNotIn('CRM backup completed', result.stdout)

    def test_archive_validation_failure_is_not_reported_as_complete(self):
        self.env.update(READY_AFTER='0', RESTORE_EXIT='50')
        result = self.run_backup()
        self.assertEqual(result.returncode, 50)
        self.assertEqual(len(self.calls('dumps')), 1)
        self.assertEqual(list(self.backups.iterdir()), [])
        self.assertNotIn('CRM backup completed', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
