"""Render all overlays; verify exact closed-gate scopes and effective workload isolation."""
import concurrent.futures,io,json,pathlib,subprocess,tarfile,tempfile,yaml
ROOT=pathlib.Path(__file__).resolve().parents[4]
WEB='8d4a1b73-7973-4dcc-a3d4-1312d871c1d4';TG='9b43e8ab-7afa-4201-8a88-99e8d256180a'
def render(path):return list(yaml.safe_load_all(subprocess.check_output(['kubectl','kustomize',str(path)],text=True,stderr=subprocess.PIPE)))
def config(objects,dep,container):
 cms={o['metadata']['name']:o.get('data',{}) for o in objects if o['kind']=='ConfigMap'};d=next(o for o in objects if o['kind']=='Deployment' and o['metadata']['name']==dep);c=next(c for c in d['spec']['template']['spec']['containers'] if c['name']==container);env={}
 for ref in c.get('envFrom',[]):
  if 'configMapRef' in ref:env.update(cms[ref['configMapRef']['name']])
 for e in c.get('env',[]):env[e['name']]=e.get('value',e.get('valueFrom'))
 return env

def verify(base='origin/main'):
 paths=sorted(p.relative_to(ROOT) for p in ROOT.glob('services/*/prod') if (p/'kustomization.yaml').exists());paths.append(pathlib.Path('platform/traefik-routes'))
 with tempfile.TemporaryDirectory() as tmp:
  oldroot=pathlib.Path(tmp);tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',base],cwd=ROOT))).extractall(oldroot)
  with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
   before=dict(zip(map(str,paths),pool.map(lambda p:render(oldroot/p),paths)));after=dict(zip(map(str,paths),pool.map(lambda p:render(ROOT/p),paths)))
  changed=[p for p in before if before[p]!=after[p]]
  expected={'services/conversation-service/prod','services/control-plane-service/prod','services/ai-agent-service/prod','services/website-gateway-service/prod','platform/traefik-routes'}
  assert set(changed)<=expected,changed
  cs=after['services/conversation-service/prod'];oldcs=before['services/conversation-service/prod']
  for name in ['conversation-service-voice-api','conversation-service-voice-worker','conversation-service-retirement-worker']:
   obj=lambda objs:next(o for o in objs if o['kind']=='Deployment' and o['metadata']['name']==name)
   assert obj(cs)==obj(oldcs),name
  assert next(o for o in cs if o['kind']=='Deployment' and o['metadata']['name']=='conversation-service')['spec']['template']['spec']['containers'][0]['name']=='conversation-service'
  api=config(cs,'conversation-service','conversation-service');web=config(cs,'conversation-service-worker','conversation-worker');tg=config(cs,'conversation-service-telegram-worker','conversation-telegram-worker');ret=config(cs,'conversation-service-retirement-worker','conversation-retirement-worker')
  for env,expected in [(api,{WEB,TG}),(web,{WEB}),(tg,{TG})]:
   assert {b['integration_id'] for b in json.loads(env['TURN_CATCH_UP_BINDINGS'])}==expected
   assert {p['integration_id'] for p in json.loads(env['TURN_SETTLING_POLICIES'])}==expected
   assert env['INBOX_LIFECYCLE_TOKEN']['secretKeyRef']['name']=='conversation-handoff-lifecycle-secret'
   assert env['HANDOFF_LIFECYCLE_TOKEN']['secretKeyRef']['name']=='conversation-handoff-lifecycle-secret'
  assert api['WRITER_ATTESTATION_REQUIRED']=='true'
  assert json.loads(api['WEBSITE_BINDINGS'])[0]['capability_generation']==1
  assert web['MANAGED_AI_BINDINGS']['secretKeyRef']['name']=='conversation-website-worker-managed-secret'
  assert tg['MANAGED_AI_BINDINGS']['secretKeyRef']['name']=='conversation-telegram-managed-ai-secret'
  assert ret['TELEGRAM_HANDOFF_INTEGRATION_IDS']==ret['WEBSITE_HANDOFF_INTEGRATION_IDS']=='[]'
  for env in [web,tg,ret]:assert 'WRITER_PRODUCERS' not in env or env['WRITER_PRODUCERS']=='[]'
  webdep=next(o for o in after['services/website-gateway-service/prod'] if o['kind']=='Deployment')
  assert next(c for c in webdep['spec']['template']['spec']['containers'] if c['name']=='website-gateway-service')['image']=='ghcr.io/chotabyorg/website-gateway-service:827a65d@sha256:f8584ce6fc541d65b44d2cd253104dbb1dd8accddf6a5363b54f86b64f4878f5'
  webobjs=after['services/website-gateway-service/prod'];gw=config(webobjs,'website-gateway-service','website-gateway-service');assert gw['COMMON_WEBSITE_MESSAGE_SESSION_ALLOWLIST']=='{}';assert set(json.loads(gw['COMMON_WEBSITE_INTEGRATIONS']))=={WEB};assert gw['COMMON_WEBSITE_TRUSTED_PROXY_CIDRS']=='10.42.0.95/32'
  tgobj=render(ROOT/'services/telegram-gateway-service/prod');tggw=config(tgobj,'telegram-gateway-service','telegram-gateway-service');assert tggw.get('TELEGRAM_HANDOFF_INTEGRATION_IDS','[]')=='[]'
  for obj in cs:
   if obj['kind']!='Deployment':continue
   spec=obj['spec']['template']['spec']
   for c in spec.get('containers',[])+spec.get('initContainers',[]):
    if c['name']!='website-tls-server':assert not any(m['name']=='conversation-website-tls-identity' for m in c.get('volumeMounts',[]))
  edge=after['platform/traefik-routes'];route=next(o for o in edge if o['metadata']['name']=='api-inbox-no-store');broad=next(o for o in edge if o['metadata']['name']=='api-chota-by');assert route['spec']['routes'][0]['services']==broad['spec']['routes'][0]['services'];assert 'PathPrefix' not in route['spec']['routes'][0]['match']
  assert before['services/chota-gateway/prod']==after['services/chota-gateway/prod']
  assert before['services/telegram-gateway-service/prod']==after['services/telegram-gateway-service/prod']
  oldgw=config(before['services/website-gateway-service/prod'],'website-gateway-service','website-gateway-service')
  for key in ['WRITER_ATTESTOR_SCOPES','WRITER_LEGACY_DRAIN_SCOPES','WRITER_PRODUCER_URL','WRITER_PRODUCER_TOKEN','MANAGED_WEBSITE_GUARDED_INTEGRATIONS','MANAGED_WEBSITE_COHORTS','CONVERSATION_S2S_TOKEN']:
   assert gw[key]==oldgw[key],key
  assert gw['MANAGED_WEBSITE_COHORTS']=='{}'
  assert tggw['TELEGRAM_CANARY_INTEGRATION_IDS']=='[]'
  for service in ['website-gateway-service','telegram-gateway-service']:
   b=before['services/'+service+'/prod'];a=after['services/'+service+'/prod']
   name=service.split('-')[0]+'-writer-producer-secret'
   assert next(o for o in b if o['kind']=='SealedSecret' and o['metadata']['name']==name)==next(o for o in a if o['kind']=='SealedSecret' and o['metadata']['name']==name)
  for service in ['conversation-service','ai-agent-service']:
   old=before['services/'+service+'/prod'];new=after['services/'+service+'/prod']
   for obj in old:
    if any(word in obj['metadata']['name'] for word in ['business','voice']):
     assert obj==next(o for o in new if o['kind']==obj['kind'] and o['metadata']['name']==obj['metadata']['name'])
  oldai=next(o for o in before['services/ai-agent-service/prod'] if o['kind']=='Deployment' and o['metadata']['name']=='ai-agent-service')['spec']['template']['spec']
  newai=next(o for o in after['services/ai-agent-service/prod'] if o['kind']=='Deployment' and o['metadata']['name']=='ai-agent-service')['spec']['template']['spec']
  assert oldai.get('initContainers')==newai.get('initContainers')
  oldenv={e['name']:e for e in next(c for c in oldai['containers'] if c['name']=='ai-agent-service').get('env',[])}
  newenv={e['name']:e for e in next(c for c in newai['containers'] if c['name']=='ai-agent-service').get('env',[])}
  assert all(newenv[k]==v for k,v in oldenv.items())
  assert set(newenv)-set(oldenv)=={'HANDOFF_AI_ENROLLED_SCOPES','HANDOFF_CONVERSATION_URL','HANDOFF_LIFECYCLE_TOKEN'}
  return {'all_overlays_rendered':len(paths),'changed_overlays':changed,'voice_and_retirement_unchanged':True,'business_resources_and_existing_ai_settings_unchanged':True,'declared_closed_admissions':True,'release_ready':False,'website_allowlist_image_pinned':True,'stage_b_runtime_acceptance_pending':True,'stage_b_base_and_drains_preserved':True,'exact_per_workload_scopes':True,'tls_key_sidecar_only':True,'gateway_auth_and_config_unchanged':True}
if __name__=='__main__':print(json.dumps(verify(__import__('sys').argv[1] if len(__import__('sys').argv)>1 else 'origin/main'),indent=2))
