"""Native Traefik error/success middleware and forwarded-header spoof tests."""
import http.client,json,pathlib,ssl,subprocess,tempfile,time,unittest,uuid,yaml
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[3]
IMAGE='rancher/mirrored-library-traefik@sha256:34d5089d0b414945342848518b383f11f5b3a645504ed87b77ffeb9d683d0e48'
def run(*args):return subprocess.check_output(['docker',*args],text=True,stderr=subprocess.PIPE).strip()
class Edge(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();p=pathlib.Path(cls.tmp.name);edge=ROOT/'platform/traefik-routes';route=yaml.safe_load((edge/'ingressroute-api-inbox.yaml').read_text())['spec']['routes'][0];middleware=yaml.safe_load((edge/'middleware-inbox-no-store.yaml').read_text())['spec']
  data={'http':{'routers':{'broad':{'rule':'Host(`api.chota.by`)','service':'gateway','entryPoints':['secure'],'tls':{}},'inbox':{'rule':route['match'],'priority':route['priority'],'service':'gateway','middlewares':['inbox-no-store'],'entryPoints':['secure'],'tls':{}}},'middlewares':{'inbox-no-store':middleware},'services':{'gateway':{'loadBalancer':{'servers':[{'url':'http://127.0.0.1:8000'}]}}}}}
  (p/'dynamic.yaml').write_text(yaml.safe_dump(data));cls.peer='prereq-edge-peer-'+uuid.uuid4().hex[:8];cls.edge='prereq-edge-'+uuid.uuid4().hex[:8]
  run('run','-d','--name',cls.peer,'-p','127.0.0.1::8443','-v',str(HERE/'edge_peer.py')+':/peer.py:ro','python:3.12-slim','python','/peer.py');cls.port=int(run('port',cls.peer,'8443').split(':')[-1])
  run('run','-d','--name',cls.edge,'--network','container:'+cls.peer,'-v',str(p)+':/config:ro',IMAGE,'--entrypoints.secure.address=:8443','--providers.file.filename=/config/dynamic.yaml','--log.level=ERROR')
  for _ in range(70):
   try:cls.call('/api/v1/inbox/cases');return
   except (ConnectionError,OSError):time.sleep(.1)
  raise RuntimeError('local edge unavailable')
 @classmethod
 def tearDownClass(cls):
  for n in [cls.edge,cls.peer]:subprocess.run(['docker','rm','-f',n],capture_output=True)
  cls.tmp.cleanup()
 @classmethod
 def call(cls,path,method='GET',auth=False,spoof=False):
  c=http.client.HTTPSConnection('127.0.0.1',cls.port,context=ssl._create_unverified_context(),timeout=3);headers={'Host':'api.chota.by'}
  if auth:headers['Authorization']='synthetic-owner'
  if spoof:headers.update({'X-Forwarded-Proto':'http','X-Real-Ip':'198.51.100.99','X-Forwarded-For':'198.51.100.99'})
  try:
   c.request(method,path,headers=headers);r=c.getresponse();return r.status,dict(r.getheaders()),json.loads(r.read())
  finally:c.close()
 def test_exact_inbox_statuses_and_methods(self):
  paths=[('/api/v1/inbox/cases','GET'),('/api/v1/inbox/cases/case-123','GET')]+[('/api/v1/inbox/cases/case-123/'+p,'POST') for p in ['claim','messages','return-to-agent']]
  for path,method in paths:
   for auth in [False,True]:
    status,headers,body=self.call(path,method,auth);self.assertEqual(status,200 if auth else 401);self.assertEqual(headers.get('Cache-Control'),'no-store');self.assertEqual(body['path'],path);self.assertEqual(body['method'],method)
 def test_adjacent_paths_unmodified(self):
  for path in ['/api/v1/inbox/casesfoo','/api/v1/inbox/cases/id/other','/api/v1/inbox/cases/id/messages/extra','/v1/instagram/callback','/health']:
   status,headers,_=self.call(path);self.assertEqual(status,401);self.assertNotIn('Cache-Control',headers)
 def test_untrusted_forwarded_headers_overwritten(self):
  _,_,body=self.call('/api/v1/inbox/cases',spoof=True);self.assertEqual(body['proto'],'https');self.assertNotEqual(body['real_ip'],'198.51.100.99')
if __name__=='__main__':unittest.main(verbosity=2)
