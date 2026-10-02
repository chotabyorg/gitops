"""Read-only delivery checks. Requires Python/PyYAML and kubectl (Kustomize v5)."""
import hashlib
import json
from pathlib import Path
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[3]
CRM = 'chota-crm-service'

def render(path):
    result = subprocess.run(['kubectl', 'kustomize', str(ROOT / path)], check=True, capture_output=True, text=True)
    return list(yaml.safe_load_all(result.stdout))

def one(objects, kind, name):
    return next(x for x in objects if x['kind'] == kind and x['metadata']['name'] == name)

def matches(selector, labels):
    return all(labels.get(k) == v for k, v in selector.items())

all_objects = []
for overlay in sorted((ROOT / 'services').glob('*/prod')):
    objects = render(overlay.relative_to(ROOT))
    all_objects += objects
    print(f'PASS render {overlay.parent.name}: {len(objects)} objects')
routes = render('platform/traefik-routes')
backend = render(f'services/{CRM}/prod')
frontend = render('services/chota-crm-web/prod')
new = backend + frontend
assert all(x['metadata']['namespace'] == 'prod' for x in new)
assert not any(x['kind'] == 'Secret' for x in new)
assert len({(x['kind'], x['metadata']['name']) for x in all_objects}) == len(all_objects), 'Cross-service resource collision'
for obj in new:
    if obj['kind'] == 'ConfigMap':
        assert not ({'DATABASE_URL', 'POSTGRES_PASSWORD', 'PGPASSWORD'} & obj.get('data', {}).keys())
    if obj['kind'] == 'PersistentVolumeClaim':
        assert obj['metadata']['annotations']['argocd.argoproj.io/sync-options'] == 'Prune=false,Delete=false'
    if obj['kind'] == 'Service':
        assert obj['spec']['type'] == 'ClusterIP'

pods = []
for obj in new:
    if obj['kind'] == 'Deployment':
        pods.append(obj['spec']['template'])
        spec = obj['spec']
        assert matches(spec['selector']['matchLabels'], spec['template']['metadata']['labels'])
        assert spec['strategy'].get('type') == 'Recreate' or spec['strategy']['rollingUpdate']['maxSurge'] == 0
        for c in spec['template']['spec']['containers']:
            assert all(k in c for k in ('startupProbe', 'readinessProbe', 'livenessProbe', 'resources'))
    elif obj['kind'] == 'CronJob':
        pods.append(obj['spec']['jobTemplate']['spec']['template'])
    elif obj['kind'] == 'Job':
        pods.append(obj['spec']['template'])

configs = {x['metadata']['name']: x for x in new if x['kind'] == 'ConfigMap'}
secret = one(backend, 'SealedSecret', CRM+'-secret')
assert set(secret['spec']['encryptedData']) == {'POSTGRES_PASSWORD', 'DATABASE_URL'}
assert secret['spec']['template']['metadata']['namespace'] == 'prod'
for pod in pods:
    spec = pod['spec']
    assert spec['automountServiceAccountToken'] is False
    assert spec['securityContext']['runAsNonRoot'] is True
    for c in spec['containers'] + spec.get('initContainers', []):
        assert '@sha256:' in c['image'], 'Floating image'
        assert c['securityContext']['readOnlyRootFilesystem'] is True
        for ref in c.get('envFrom', []):
            assert ref['configMapRef']['name'] in configs
        for env in c.get('env', []):
            if 'valueFrom' in env:
                ref = env['valueFrom']['secretKeyRef']
                assert ref['name'] == CRM+'-secret' and ref['key'] in secret['spec']['encryptedData']
    for v in spec.get('volumes', []):
        if 'configMap' in v:
            assert v['configMap']['name'] in configs, 'Unrewritten ConfigMap reference'

# A service must select exactly its intended Deployment, never API plus Postgres.
deployments = [x for x in new if x['kind'] == 'Deployment']
for service in [x for x in new if x['kind'] == 'Service']:
    selected = [d for d in deployments if matches(service['spec']['selector'], d['spec']['template']['metadata']['labels'])]
    assert len(selected) == 1 and selected[0]['metadata']['name'] == service['metadata']['name']
pg = one(backend, 'Deployment', CRM+'-postgres')
assert pg['spec']['strategy']['type'] == 'Recreate'
assert '/var/lib/postgresql' in [v['mountPath'] for v in pg['spec']['template']['spec']['containers'][0]['volumeMounts']]
cron = one(backend, 'CronJob', CRM+'-backup')['spec']
assert cron['concurrencyPolicy'] == 'Forbid' and cron['timeZone'] == 'Etc/UTC' and cron['schedule'] == '15 2 * * *'
assert cron['jobTemplate']['spec']['activeDeadlineSeconds'] == 900
job = one(backend, 'Job', CRM+'-backup-initial-v01')
assert job['spec'] == cron['jobTemplate']['spec']
assert one(backend, 'NetworkPolicy', CRM+'-api')['spec']['ingress'][0]['from'] == [{'podSelector': {'matchLabels': {'app': 'chota-gateway'}}}]
assert one(frontend, 'NetworkPolicy', 'chota-crm-web')['spec']['egress'] == []
assert not any(x['kind'] == 'IngressRoute' and CRM in str(x['spec']) for x in routes)
assert one(routes, 'IngressRoute', 'crm-chota-by')['spec']['routes'][0]['services'][0]['name'] == 'chota-crm-web'

expected = {
    'backup.sh': '6d403b5c2c2efabd74b05a7cb394ea66e881152bcd038cc3e22e299fcc7d4730',
    'restore-check.sh': '19c5e5d0bf583bbbbad2c16f97bd24e3cb98f669054bc3c4c6f051855a11eee5',
}
for name, digest in expected.items():
    assert hashlib.sha256((ROOT / f'services/{CRM}/prod/{name}').read_bytes()).hexdigest() == digest
config = ROOT / 'services/chota-gateway/prod/krakend.json'
assert hashlib.sha256(config.read_bytes()).hexdigest() == 'c9913f040992db88d080133360cee2a838cac3cfaca628e4ded2557bdffa0ac3'
gateway = json.loads(config.read_text())
assert len(gateway['endpoints']) == 128
assert len([e for e in gateway['endpoints'] if e['endpoint'].startswith('/api/crm/v1')]) == 57
print('PASS: deployment selectors, immutable images, private boundaries, ConfigMap/Secret references, probes, resource budgets, retained PVCs, migration/backup wiring, reviewed script/config hashes')

restore = render('services/chota-crm-service/operations/restore')
assert len(restore) == 3 and not any(x['kind'] in ('Secret', 'PersistentVolumeClaim', 'Service') for x in restore)
restore_job = one(restore, 'Job', 'chota-crm-restore-check-v01')
restore_pod = restore_job['spec']['template']['spec']
assert all(not c.get('envFrom') and not any('valueFrom' in e for e in c.get('env', [])) for c in restore_pod['containers'])
assert next(v for v in restore_pod['volumes'] if v['name'] == 'backups')['persistentVolumeClaim']['readOnly'] is True
assert one(restore, 'NetworkPolicy', 'chota-crm-restore-check')['spec']['egress'] == []
assert (ROOT / f'services/{CRM}/operations/restore/restore-check.sh').read_bytes() == (ROOT / f'services/{CRM}/prod/restore-check.sh').read_bytes()
print('PASS: inert restore bundle has no production credentials, public service or PVC deletion target')
