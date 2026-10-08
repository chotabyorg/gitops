#!/usr/bin/env python3
"""Disposable real NGINX mTLS proof. No production network, ports or credentials.

Requires Docker, openssl, kubectl, Python3/PyYAML. All Docker resources are uniquely
named, use an internal network, and are deleted in finally. TLS keys are synthetic.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
import yaml

ROOT = Path(__file__).resolve().parents[2]
IMAGE = 'docker.io/library/nginx@sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe'
SERVER = 'chota-crm-service.prod.svc.cluster.local'
PYTHON = 'python:3.12-slim'


def run(args, *, ok=True, **kw):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)
    if ok and result.returncode:
        raise RuntimeError(f'Command failed: {args[:3]}\n{result.stderr[:1500]}')
    return result


def render(svc):
    return list(yaml.safe_load_all(run(['kubectl', 'kustomize', str(ROOT/'services'/svc/'prod')]).stdout))


def one(objects, kind, name):
    return next(x for x in objects if x['kind'] == kind and x['metadata']['name'] == name)


def static_checks():
    crm_only = '--stage=crm' in sys.argv
    roles = [('chota-crm-service', 'server')] if crm_only else [('ai-agent-service', 'client'), ('chota-crm-service', 'server')]
    for svc, role in roles:
        objects = render(svc)
        pod = one(objects, 'Deployment', svc)['spec']['template']['spec']
        sidecar = next(c for c in pod['containers'] if c['name'] == 'business-tls-'+role)
        if '--require-secrets' in sys.argv:
            name = 'ai-business-tls-v1' if role == 'client' else 'crm-business-tls-v1'
            sealed = one(objects, 'SealedSecret', name)
            assert sealed['metadata']['namespace'] == 'prod'
            assert sealed['spec']['template']['metadata'] == {'name': name, 'namespace': 'prod'}
            assert sealed['spec']['template']['type'] == 'kubernetes.io/tls'
            data = sealed['spec']['encryptedData']
            assert set(data) == {'ca.crt', 'tls.crt', 'tls.key'}
            assert set(sealed['spec']) == {'encryptedData', 'template'}
            assert not any(k in sealed['spec']['template'] for k in ('data', 'stringData'))
            assert sealed['metadata']['annotations']['argocd.argoproj.io/sync-wave'] == '-2'
            assert all(v.startswith('Ag') and len(v) > 100 for v in data.values())
            assert not sealed['metadata'].get('annotations', {}).get('sealedsecrets.bitnami.com/cluster-wide')
            assert not sealed['metadata'].get('annotations', {}).get('sealedsecrets.bitnami.com/namespace-wide')
        assert sidecar['image'] == IMAGE
        assert sidecar['securityContext']['readOnlyRootFilesystem']
        assert sidecar['securityContext']['runAsNonRoot']
        for c in pod['containers'] + pod.get('initContainers', []):
            if c is not sidecar:
                assert not any(v['mountPath'] == '/etc/business-tls' or v['name'].endswith('-tls-identity') for v in c.get('volumeMounts', []))
        assert not sidecar.get('env') and not sidecar.get('envFrom')
    ai = render('ai-agent-service')
    if not crm_only:
        config = next(x for x in ai if x['kind'] == 'ConfigMap' and 'BUSINESS_CRM_URL' in x.get('data', {}))['data']
        assert config['BUSINESS_CAPABILITIES_ENABLED'] == 'false'
        assert config['BUSINESS_CRM_URL'] == 'http://127.0.0.1:18081'
        assert config['BUSINESS_CRM_KEY_ID'] == 'chota-business-prod-20261008-01'
        if '--require-secrets' in sys.argv:
            signing = one(ai, 'SealedSecret', 'ai-business-v2-signing')
            assert set(signing['spec']) == {'encryptedData', 'template'}
            assert set(signing['spec']['encryptedData']) == {'BUSINESS_CRM_PRIVATE_KEY'}
            assert signing['spec']['encryptedData']['BUSINESS_CRM_PRIVATE_KEY'].startswith('Ag')
            assert not any(k in signing['spec']['template'] for k in ('data','stringData'))
            for o in ai:
                if o['kind'] in ('Deployment','Job'):
                    spec=o['spec']['template']['spec']
                    for c in spec.get('containers',[])+spec.get('initContainers',[]):
                        refs=[e['valueFrom']['secretKeyRef'] for e in c.get('env',[]) if 'valueFrom' in e and 'secretKeyRef' in e['valueFrom'] and e['valueFrom']['secretKeyRef']['name']=='ai-business-v2-signing']
                        if c['name']=='ai-agent-service':
                            assert refs == [{'name':'ai-business-v2-signing','key':'BUSINESS_CRM_PRIVATE_KEY'}]
                        else:
                            assert not refs
                        assert not any(e.get('secretRef',{}).get('name')=='ai-business-v2-signing' for e in c.get('envFrom',[]))
    crm = render('chota-crm-service')
    public_config = next(x for x in crm if x['kind']=='ConfigMap' and 'CRM_AGENT_PUBLIC_KEYS_JSON' in x.get('data',{}))['data']
    assert set(json.loads(public_config['CRM_AGENT_PUBLIC_KEYS_JSON'])) == {'chota-business-prod-20261008-01'}
    ingress = one(crm, 'NetworkPolicy', 'chota-crm-service-api')['spec']['ingress']
    assert ingress == [
        {'from': [{'podSelector': {'matchLabels': {'app': 'chota-gateway'}}}], 'ports': [{'protocol': 'TCP', 'port': 8000}]},
        {'from': [{'podSelector': {'matchLabels': {'app': 'ai-agent-service', 'component': 'api'}}}], 'ports': [{'protocol': 'TCP', 'port': 8443}]}]
    service = one(crm, 'Service', 'chota-crm-service')['spec']
    assert service['type'] == 'ClusterIP'
    assert {x['port'] for x in service['ports']} == {8000, 8443}
    certs = ROOT/'docs/business-transport/public-certificates'
    for leaf,purpose in [('ai-client.crt','sslclient'),('crm-server.crt','sslserver')]:
        args=['openssl','verify','-CAfile',str(certs/'transport-ca.crt'),'-purpose',purpose]
        if purpose=='sslserver': args += ['-verify_hostname',SERVER]
        run(args+[str(certs/leaf)])
        run(['openssl','x509','-in',str(certs/leaf),'-noout','-checkend','2592000'])
    subject=run(['openssl','x509','-in',str(certs/'ai-client.crt'),'-noout','-subject','-nameopt','RFC2253']).stdout.strip()
    assert subject=='subject=CN=ai-agent-service-business'
    print('PASS selected stage, sidecar-only TLS mounts, exact private policy, real public certificate trust/expiry')


BACKEND = '''from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, time
class Handler(BaseHTTPRequestHandler):
 def do_GET(self): self.handle_request()
 def do_POST(self): self.handle_request()
 def do_PUT(self): self.handle_request()
 def handle_request(self):
  length=int(self.headers.get('Content-Length','0'))
  body=self.rfile.read(length) if length else b''
  if self.headers.get('Transfer-Encoding','').lower()=='chunked':
   while True:
    chunk_size=int(self.rfile.readline().strip(),16)
    if not chunk_size:
     self.rfile.readline()
     break
    body+=self.rfile.read(chunk_size)
    self.rfile.read(2)
  with open('/evidence/requests.jsonl','a') as f:
   f.write(json.dumps({'path':self.path,'method':self.command,'body':body.decode(),'auth':self.headers.get('Authorization'),'cookie':self.headers.get('Cookie'),'owner':self.headers.get('X-User-Id')})+'\\n')
  if self.path.endswith('/drop'):
   self.close_connection=True
   return
  if self.path.endswith('/slow'): time.sleep(7)
  self.send_response(503 if self.path.endswith('/error') else 204)
  self.send_header('Content-Length','0')
  self.end_headers()
 def log_message(self,*args): pass
ThreadingHTTPServer(('0.0.0.0',8000),Handler).serve_forever()
'''


def main():
    static_checks()
    prefix = 'chota-mtls-'+uuid.uuid4().hex[:10]
    network = prefix+'-net'
    backend = prefix+'-backend'
    client = prefix+'-client'
    server = prefix+'-server'
    containers = [client, server, backend]
    with tempfile.TemporaryDirectory(prefix='chota-mtls-', dir='/private/tmp') as temporary:
        tmp = Path(temporary)
        os.chmod(tmp, 0o755)
        for directory in ['evidence', 'fixture', 'client', 'server', 'wrong-host', 'wrong-server-ca']:
            (tmp/directory).mkdir()
        os.chmod(tmp/'evidence', 0o777)
        (tmp/'backend.py').write_text(BACKEND)
        fixture = tmp/'fixture'
        def openssl(*args):
            run(['openssl', *map(str, args)])
        def ca(name):
            openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN='+name,
                    '-keyout', fixture/(name+'.key'), '-out', fixture/(name+'.crt'))
        ca('test-ca'); ca('wrong-ca')
        def cert(name, cn, kind, issuer='test-ca', san=None):
            openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN='+cn,
                    '-keyout', fixture/(name+'.key'), '-out', fixture/(name+'.csr'))
            (fixture/(name+'.ext')).write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage='+kind+'\n'+('subjectAltName=DNS:'+san+'\n' if san else ''))
            openssl('x509', '-req', '-in', fixture/(name+'.csr'), '-CA', fixture/(issuer+'.crt'), '-CAkey', fixture/(issuer+'.key'),
                    '-CAcreateserial', '-days', '1', '-extfile', fixture/(name+'.ext'), '-out', fixture/(name+'.crt'))
        cert('server', SERVER, 'serverAuth', san=SERVER)
        cert('client', 'ai-agent-service-business', 'clientAuth')
        cert('wrong-client', 'ai-agent-service-business', 'clientAuth', issuer='wrong-ca')
        cert('wrong-identity', 'other-service', 'clientAuth')
        cert('wrong-host', 'wrong.example', 'serverAuth', san='wrong.example')
        cert('wrong-server-ca', SERVER, 'serverAuth', issuer='wrong-ca', san=SERVER)
        for variant in ['client', 'server', 'wrong-host', 'wrong-server-ca']:
            for source, dest in [('test-ca.crt', 'ca.crt'), (variant+'.crt', 'tls.crt'), (variant+'.key', 'tls.key')]:
                (tmp/variant/dest).write_bytes((fixture/source).read_bytes())
                os.chmod(tmp/variant/dest, 0o444)
        for file in fixture.iterdir():
            os.chmod(file, 0o444)
        def docker(*args, **kwargs): return run(['docker', *map(str, args)], **kwargs)
        def start_server(variant='server'):
            docker('run', '-d', '--name', server, '--network', 'container:'+backend,
                   '--user', '10001:10001', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                   '--memory', '64m', '--cpus', '.2', '--tmpfs', '/tmp:rw,noexec,nosuid,size=8m,uid=10001,gid=10001',
                   '-v', f'{tmp/variant}:/etc/business-tls:ro',
                   '-v', f'{ROOT}/services/chota-crm-service/prod/business-transport:/etc/business-proxy:ro',
                   '--entrypoint', 'nginx', IMAGE, '-c', '/etc/business-proxy/nginx.conf', '-g', 'daemon off;')
            wait_ready(server, 18082)
        def wait_ready(container, port):
            for _ in range(30):
                if docker('exec', container, 'curl', '--fail', '--silent', '--max-time', '1', f'http://127.0.0.1:{port}/healthz', ok=False).returncode == 0:
                    return
                time.sleep(.2)
            raise RuntimeError('Proxy health failed: '+container+' '+docker('logs',container,ok=False).stderr)
        def count(path):
            f=tmp/'evidence/requests.jsonl'
            return sum(row['path']==path for row in (json.loads(x) for x in f.read_text().splitlines())) if f.exists() else 0
        def request(path, *, direct=False, cert_name=None, method='POST'):
            base = 'https://'+SERVER+':8443' if direct else 'http://127.0.0.1:18081'
            args=['exec', client, 'curl', '--silent', '--show-error', '--max-time', '9', '-o', '/dev/null', '-w', '%{http_code}',
                  '-X', method, '-H', 'Content-Type: application/json', '-H', 'Authorization: Bearer synthetic-auth',
                  '-H', 'Cookie: access_token=synthetic-cookie', '-H', 'X-User-Id: synthetic-owner', '--data-binary', '{"synthetic":true}']
            if direct:
                args += ['--cacert', '/fixture/test-ca.crt']
                if cert_name: args += ['--cert','/fixture/'+cert_name+'.crt','--key','/fixture/'+cert_name+'.key']
            return docker(*args, base+path, ok=False).stdout
        try:
            docker('network', 'create', '--internal', network)
            docker('run', '-d', '--name', backend, '--network', network, '--network-alias', SERVER,
                   '--user', '10001:10001', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                   '-v', f'{tmp}/backend.py:/fixture/backend.py:ro', '-v', f'{tmp}/evidence:/evidence',
                   '--entrypoint', 'python', PYTHON, '/fixture/backend.py')
            start_server()
            docker('run', '-d', '--name', client, '--network', network,
                   '--user', '10001:10001', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                   '--memory', '64m', '--cpus', '.2', '--tmpfs', '/tmp:rw,noexec,nosuid,size=8m,uid=10001,gid=10001',
                   '-v', f'{tmp}/client:/etc/business-tls:ro', '-v', f'{fixture}:/fixture:ro',
                   '-v', f'{ROOT}/services/ai-agent-service/prod/business-transport:/etc/business-proxy:ro',
                   '--entrypoint', 'nginx', IMAGE, '-c', '/etc/business-proxy/nginx.conf', '-g', 'daemon off;')
            wait_ready(client, 18081)
            for suffix, expected in [('ok','204'), ('error','503'), ('drop','502'), ('slow','504')]:
                path='/internal/agent/v1/'+suffix
                status=request(path)
                assert status==expected, (suffix,status)
                assert count(path)==1, (suffix,count(path))
            print('PASS valid mutual TLS; POST success/error/drop/timeout forwarded exactly once')
            for _ in range(2):
                assert request('/internal/agent/v1/read',method='GET')=='204'
            assert count('/internal/agent/v1/read')==2
            print('PASS intentional repeated reads are not cached')
            rows=[json.loads(x) for x in (tmp/'evidence/requests.jsonl').read_text().splitlines()]
            assert all(x['auth']=='Bearer synthetic-auth' and x['cookie']=='access_token=synthetic-cookie' and x['owner']=='synthetic-owner' and x['body']=='{"synthetic":true}' for x in rows)
            print('PASS exact body and required assertion/cookie/owner headers preserved')
            for identity in [None,'wrong-client','wrong-identity']:
                path='/internal/agent/v1/denied-'+str(identity)
                assert request(path,direct=True,cert_name=identity) in ('400','403'), identity
                assert count(path)==0
            assert request('/api/crm/v1/workspaces')=='404'
            assert count('/api/crm/v1/workspaces')==0
            print('PASS missing/untrusted/wrong-identity client denied; non-agent path denied')
            for variant in ['wrong-host','wrong-server-ca']:
                docker('rm','-f',server)
                start_server(variant)
                path='/internal/agent/v1/'+variant
                assert request(path)=='502'
                assert count(path)==0
            print('PASS server hostname and issuer verified; no request reaches backend on failure')
            logs=''.join(docker('logs',name,ok=False).stdout+docker('logs',name,ok=False).stderr for name in containers)
            assert 'synthetic-auth' not in logs and 'synthetic-cookie' not in logs
            print('PASS no synthetic assertion/cookie in logs; resources cleanup follows')
        finally:
            for name in containers: docker('rm','-f',name,ok=False)
            docker('network','rm',network,ok=False)


if __name__=='__main__':
    main()
