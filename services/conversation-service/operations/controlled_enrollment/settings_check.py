import subprocess,json,pathlib,yaml,os,hashlib,tempfile
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--workspace',type=pathlib.Path,required=True);parser.add_argument('--website-image');args=parser.parse_args()
root=args.workspace.resolve();repo=pathlib.Path(__file__).resolve().parents[4];ev=pathlib.Path(__file__).resolve().parent/'fixtures'
registry={o['name']:o.get('entries',{}) for o in map(json.loads,(ev/'registries.jsonl').read_text().splitlines())}
registry['conversation-common-website-principals-secret']={'API_AUTH_PRINCIPALS':registry['conversation-business-principals-secret']['API_AUTH_PRINCIPALS']+[{'principal_id':'main-common-website-gateway','role':'WEBSITE','token':True,'grants':registry['conversation-business-principals-secret']['API_AUTH_PRINCIPALS'][0]['grants']}]}
registry['conversation-website-worker-managed-secret']={'MANAGED_AI_BINDINGS':[registry['conversation-beauty-managed-secret']['MANAGED_AI_BINDINGS'][0]]}
registry['ai-voice-managed-secret']={'MANAGED_AI_AUTH_PRINCIPALS':json.loads((ev/'remote-registry-preservation.json').read_text())['ai_principals']}
def token(s):return 'fixture-'+hashlib.sha256(s.encode()).hexdigest()
def material(v,path):
 if isinstance(v,list):return [material(x,path+str(i)) for i,x in enumerate(v)]
 if isinstance(v,dict):return {k:token(path+k) if x is True else material(x,path+k) for k,x in v.items()}
 return v
registry={n:{k:json.dumps(material(v,n+k)) for k,v in data.items()} for n,data in registry.items()}
def secret(n,k):
 if k=='DATABASE_URL':return 'postgresql+asyncpg://fixture:fixture@127.0.0.1/fixture'
 if n in registry and k in registry[n]:return registry[n][k]
 if k=='WRITER_PRODUCERS':return json.dumps([{'principal_id':'fixture-writer','token':token('producer'),'grants':[{'owner_id':'dc3dd7eb-536f-45d4-84f2-c8d35575d928','integration_id':'8d4a1b73-7973-4dcc-a3d4-1312d871c1d4','agent_id':'0b750714-af8d-4d8c-8fdc-4ddfeda98af9','channel':'WEBSITE_WIDGET'}]}])
 if k=='ENCRYPTION_KEY':return 'A'*43+'='
 return token(n+k)
checks=[]
for svc in ['conversation-service','ai-agent-service','control-plane-service','website-gateway-service','telegram-gateway-service']:
 objs=list(yaml.safe_load_all(subprocess.check_output(['kubectl','kustomize',str(repo/f'services/{svc}/prod')],text=True)));cms={o['metadata']['name']:o.get('data',{}) for o in objs if o['kind']=='ConfigMap'}
 for dep in [o for o in objs if o['kind']=='Deployment']:
  if 'voice' in dep['metadata']['name'] or 'postgres' in dep['metadata']['name'] or 'redis' in dep['metadata']['name']:continue
  for c in dep['spec']['template']['spec'].get('containers',[])+dep['spec']['template']['spec'].get('initContainers',[]):
   if c['name'] in ['website-tls-server','business-tls-client']:continue
   env={}
   for source in c.get('envFrom',[]):
    if 'configMapRef' in source:env.update(cms[source['configMapRef']['name']])
   for e in c.get('env',[]):
    if 'value' in e:env[e['name']]=e['value']
    elif 'secretKeyRef' in e.get('valueFrom',{}):s=e['valueFrom']['secretKeyRef'];env[e['name']]=secret(s['name'],s['key'])
   if svc=='telegram-gateway-service':env['INTERNAL_API_TOKEN']=token('telegram-internal')
   if svc=='website-gateway-service':
    env['CONVERSATION_S2S_TOKEN']=token('old-web');env['COMMON_WEBSITE_CONVERSATION_CA_FILE']=str(repo/'services/website-gateway-service/prod/common-website-ca.crt')
   if svc=='ai-agent-service':
    env.setdefault('CHAT_S2S_TOKEN',token('chat'));env.setdefault('MCP_CREDENTIALS_ENCRYPTION_KEY','A'*43+'=')
   if c['name']=='conversation-migrations':continue
   src=root/f'.native-handoff-20261022/sources/{svc}'
   if svc=='conversation-service':src=root/'.native-handoff-20261022/final-sources/conversation-service'
   if svc=='website-gateway-service':src=root/'worktrees/website-common-message-allowlist'
   if svc=='telegram-gateway-service':src=root/'.native-handoff-20261022/final-sources/telegram-gateway-service'
   py=root/f'.native-handoff-20261022/venvs/{svc}/bin/python'
   script='from core.config import Settings; Settings(_env_file=None); print("settings_ok")'
   if svc in ['website-gateway-service','telegram-gateway-service']:
    script="""import os
from services.writer_attestor import Parent, scopes, matches
allowed=scopes(); drains=scopes('WRITER_LEGACY_DRAIN_SCOPES')
assert len(allowed)==len(drains)==1
assert all(any(matches(row,scope) for row in drains) for scope in allowed)
assert os.environ['WRITER_PRODUCER_URL']=='http://conversation-service:8000'
assert 32<=len(os.environ['WRITER_PRODUCER_TOKEN'])<=256
before=dict(os.environ); child=Parent(None,allowed).child_environment('/tmp/fixture.sock')
assert 'WRITER_PRODUCER_TOKEN' not in child and 'WRITER_PRODUCER_URL' not in child
assert child['WRITER_ATTESTOR_SCOPES']==before['WRITER_ATTESTOR_SCOPES']
assert child['WRITER_LEGACY_DRAIN_SCOPES']==before['WRITER_LEGACY_DRAIN_SCOPES']
for key in ['COMMON_WEBSITE_S2S_TOKEN','COMMON_WEBSITE_CONVERSATION_CA_FILE']:
 if key in before:assert child[key]==before[key]
os.environ.clear(); os.environ.update(child)
from core.config import Settings
Settings(_env_file=None)
print('settings_and_supervised_child_ok')"""
   if svc=='website-gateway-service' and args.website_image:
    env['COMMON_WEBSITE_CONVERSATION_CA_FILE']='/fixture-ca.crt'
    with tempfile.NamedTemporaryFile(mode='w',suffix='.env') as fixture:
     fixture.write(''.join(k+'='+v+'\n' for k,v in env.items()));fixture.flush()
     command=['docker','run','--rm','--network','none','--platform','linux/amd64','--env-file',fixture.name,'-v',str(repo/'services/website-gateway-service/prod/common-website-ca.crt')+':/fixture-ca.crt:ro','--entrypoint','python',args.website_image,'-c',script]
     run=subprocess.run(command,capture_output=True,text=True)
     # Confirm the image enforces the new field, rather than silently ignoring it.
     malformed=dict(env,COMMON_WEBSITE_MESSAGE_SESSION_ALLOWLIST='{"invalid":"*"}')
     fixture.seek(0);fixture.truncate();fixture.write(''.join(k+'='+v+'\n' for k,v in malformed.items()));fixture.flush()
     negative=subprocess.run(command,capture_output=True,text=True)
     assert negative.returncode!=0,'Website image ignored malformed admission fence'
   else:
    run=subprocess.run([str(py),'-c',script],cwd=src,env={**os.environ,**env,'PYTHONPATH':str(src)},capture_output=True,text=True)
   checks.append({'deployment':dep['metadata']['name'],'container':c['name'],'ok':run.returncode==0})
   if run.returncode:print(c['name'],run.stderr[-2200:])
print(json.dumps(checks,indent=2))
assert all(c['ok'] for c in checks)
