"""Disposable local deployment verification; no ports, production data or credentials.

Optional argument: reviewed local backend image. Default is the pinned release.
All Docker resources have a unique test-owned prefix and are removed in finally.
"""
import subprocess,time,sys,uuid
from pathlib import Path
BASE=Path(__file__).resolve().parents[1] / 'prod'
PG='postgres:18.6-alpine3.24@sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873'
API=sys.argv[1] if len(sys.argv)>1 else 'ghcr.io/chotabyorg/chota-crm-service@sha256:5480abfddfcc030d17107ba820777ff02467924aaa6472abd3b9c13c412d2df0'
prefix='crm-gitops-validation-'+uuid.uuid4().hex[:8]
containers=[];volumes=[];network_created=False
def run(args,check=True):
 r=subprocess.run(['docker',*args],capture_output=True,text=True)
 if check and r.returncode:
  print('FAILED command category',args[0]); print(r.stderr[:1000]);raise RuntimeError('Local verification failed')
 return r
common=['--network',prefix,'--read-only','--cap-drop=ALL','--security-opt=no-new-privileges','--memory','256m','--cpus','0.5','--tmpfs','/tmp:rw,noexec,nosuid,uid=10001,gid=10001,size=67108864','--user','10001:10001','-e','DATABASE_URL=postgresql+asyncpg://crm_test@source:5432/crm_test','-e','PYTHONPATH=/app','-v',f'{BASE}:/opt/crm:ro']
def container(name,args):
 containers.append(name);return run(['run','-d','--name',name,*args]).stdout.strip()
def pg(name,volume,alias):
 return container(name,['--network',prefix,'--network-alias',alias,'--read-only','--user','70:70','--cap-drop=ALL','--security-opt=no-new-privileges','--memory','384m','--cpus','0.5','--tmpfs','/var/run/postgresql:uid=70,gid=70,size=16777216','--tmpfs','/tmp:uid=70,gid=70,size=67108864','--mount',f'type=volume,src={volume},dst=/var/lib/postgresql','-e','POSTGRES_USER=crm_test','-e','POSTGRES_DB=crm_test','-e','POSTGRES_HOST_AUTH_METHOD=trust',PG,'-c','shared_buffers=64MB','-c','max_connections=30','-c','work_mem=4MB','-c','maintenance_work_mem=32MB','-c','log_min_error_statement=panic'])
def sql(query):return run(['exec',prefix+'-source','psql','-X','-U','crm_test','-d','crm_test','-Atc',query]).stdout.strip()
try:
 assert run(['network','inspect',prefix],False).returncode!=0,'Test network already exists'
 run(['network','create','--internal',prefix]);network_created=True
 for suffix in ['source','target','backup']:
  v=prefix+'-'+suffix;run(['volume','create',v]);volumes.append(v);run(['run','--rm','--network','none','--user','0','-v',v+':/volume',PG,'chown','70:70','/volume'])
 # Both migration processes start with no DB, proving bounded startup waits.
 for s in ['migrate-a','migrate-b']:container(prefix+'-'+s,[*common,API,'python','/opt/crm/migrate.py'])
 time.sleep(3)
 assert all(run(['inspect','--format','{{.State.Running}}',prefix+'-'+s]).stdout.strip()=='true' for s in ['migrate-a','migrate-b'])
 pg(prefix+'-source',volumes[0],'source')
 for s in ['migrate-a','migrate-b']:
  assert run(['wait',prefix+'-'+s]).stdout.strip()=='0'
  assert 'CRM migration completed' in run(['logs',prefix+'-'+s]).stdout
 assert sql('SELECT version_num FROM alembic_version')=='0001_crm'
 print('PASS: delayed DB startup, concurrent migrations, correct schema')
 # A held lock prevents a fresh attempt progressing until that exact lock releases.
 holder=container(prefix+'-holder',['--network',prefix,PG,'psql','-h','source','-U','crm_test','-d','crm_test','-c','SELECT pg_advisory_lock(4348524); SELECT pg_sleep(30)'])
 time.sleep(1)
 container(prefix+'-blocked',[*common,API,'python','/opt/crm/migrate.py'])
 time.sleep(3)
 assert int(sql("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted"))>=1
 assert 'lock acquired' not in run(['logs',prefix+'-blocked']).stdout
 run(['rm','-f',prefix+'-holder']);containers.remove(prefix+'-holder')
 assert run(['wait',prefix+'-blocked']).stdout.strip()=='0'
 print('PASS: advisory lock blocks concurrent rollout until released')
 container(prefix+'-api',[*common,API])
 for _ in range(30):
  r=run(['exec',prefix+'-api','python','-c',"import urllib.request; assert urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3).status==200; assert urllib.request.urlopen('http://127.0.0.1:8000/ready',timeout=3).status==200"],False)
  if not r.returncode:break
  time.sleep(1)
 else:raise RuntimeError('API readiness failure')
 print('PASS: non-root read-only API health/readiness with declared memory/CPU budget')
 run(['restart',prefix+'-source'])
 for _ in range(30):
  r=run(['exec',prefix+'-source','pg_isready','-U','crm_test','-d','crm_test'],False)
  if not r.returncode:break
  time.sleep(1)
 assert sql('SELECT version_num FROM alembic_version')=='0001_crm'
 print('PASS: non-root read-only PG18 restart persists schema at PG18 mount')
 backup=['--network',prefix,'--read-only','--user','70:70','--cap-drop=ALL','--security-opt=no-new-privileges','--memory','128m','--cpus','0.25','--tmpfs','/tmp:uid=70,gid=70,size=33554432','--mount',f'type=volume,src={volumes[2]},dst=/backups','-v',f'{BASE}:/opt/crm-backup:ro','-e','PGHOST=source','-e','PGUSER=crm_test','-e','PGDATABASE=crm_test','-e','BACKUP_DIR=/backups','-e','PGCONNECT_TIMEOUT=10','-e','PGOPTIONS=-c statement_timeout=600000 -c lock_timeout=30000']
 r=run(['run','--rm',*backup,PG,'sh','/opt/crm-backup/backup-ready.sh']);assert 'CRM backup completed' in r.stdout
 r=run(['run','--rm','--network','none','--user','70:70','--mount',f'type=volume,src={volumes[2]},dst=/backups,readonly',PG,'sh','-c',"set -- /backups/chotacrm-*.dump; test $# -eq 1; test \"$(stat -c %a \"$1\")\" = 600; pg_restore --list \"$1\" >/dev/null"]);assert r.returncode==0
 print('PASS: exact backup helper, separate volume, UID70, mode0600, valid archive')
 pg(prefix+'-target',volumes[1],'target')
 for _ in range(30):
  r=run(['exec',prefix+'-target','pg_isready','-U','crm_test'],False)
  if not r.returncode:break
  time.sleep(1)
 restore=[*backup,'-e','PGHOST=target','-e','PGDATABASE=crm_restore_gitops']
 r=run(['run','--rm',*restore,PG,'sh','-c','set -- /backups/chotacrm-*.dump; export RESTORE_FILE="$1"; sh /opt/crm-backup/restore-check.sh'])
 assert 'Restore verification complete' in r.stdout
 run(['exec',prefix+'-target','dropdb','-U','crm_test','crm_restore_gitops'])
 print('PASS: exact restore helper into separate disposable PG18; temporary DB removed')
 restore_scripts=BASE.parent / 'operations' / 'restore'
 wrapper=['--network','none','--read-only','--user','70:70','--cap-drop=ALL','--security-opt=no-new-privileges','--memory','256m','--cpus','0.5','--tmpfs','/tmp:uid=70,gid=70,size=33554432','--tmpfs','/var/lib/postgresql:uid=70,gid=70,size=268435456','--tmpfs','/var/run/postgresql:uid=70,gid=70,size=16777216','--mount',f'type=volume,src={volumes[2]},dst=/backups,readonly','-v',f'{restore_scripts}:/opt/restore:ro']
 r=run(['run','--rm',*wrapper,PG,'sh','-c','set -- /backups/chotacrm-*.dump; export RESTORE_FILE="$1"; sh /opt/restore/restore.sh'])
 assert 'CRM disposable database removed; backup volume remained read-only' in r.stdout
 print('PASS: operator restore wrapper, no network/secrets, read-only archive, local socket DB cleanup')
 r=run(['run','--rm',*wrapper,'-e','RESTORE_FILE=/backups/REPLACE_WITH_COMPLETED_TIMESTAMP.dump',PG,'sh','/opt/restore/restore.sh'],False)
 assert r.returncode!=0 and 'Refusing unexpected backup path' in r.stderr
 print('PASS: incomplete restore template fails closed before database creation')

 print(run(['stats','--no-stream','--format','{{.Name}} {{.MemUsage}}',prefix+'-api',prefix+'-source']).stdout.strip())
finally:
 for c in reversed(containers):run(['rm','-f',c],False)
 for v in volumes:run(['volume','rm',v],False)
 if network_created:run(['network','rm',prefix],False)
 print('Cleanup: only verifier-owned containers, volumes and network removed')
