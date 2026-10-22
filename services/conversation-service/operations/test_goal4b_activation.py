"""Configuration-only QA checks: complete renders, exact scope, retained ciphertext.

No Kubernetes connection, credential decryption, provider traffic or plaintext
test fixtures. Existing image/network/selector checks remain in release suite.
"""
import copy
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

import yaml

from test_goal4b_release import REPO, QA_BINDING, QA_INTEGRATION, environment, render, resource

BASE = '5ca25801830e7a90003c4465681329d1d56551fa'
OWNER = QA_BINDING['owner_id']
AGENT = QA_BINDING['agent_id']
GRANT = dict(owner_id=OWNER,integration_id=QA_INTEGRATION,channel='TELEGRAM',
             provider_namespace='main-chota.telegram.v1')

def original(path):
    p = subprocess.run(['git','-C',str(REPO),'show',BASE+':'+path],capture_output=True,check=True)
    return json.loads(p.stdout)

def container(documents, deployment):
    return resource(documents,'Deployment',deployment)['spec']['template']['spec']['containers'][0]

def reference(documents, deployment, variable):
    entry = next(e for e in container(documents,deployment)['env'] if e['name']==variable)
    return entry['valueFrom']['secretKeyRef']

class Goal4BActivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conversation=render('conversation-service')
        cls.gateway=render('telegram-gateway-service')
        cls.ai=render('ai-agent-service')
        cls.scope=json.loads((REPO/'services/conversation-service/GOAL4B-ACTIVATION.json').read_text())

    def test_one_exact_scope_and_narrow_principal_roles(self):
        self.assertEqual(self.scope['phase'],'activation')
        self.assertEqual(self.scope['gateway_binding'],QA_BINDING)
        self.assertEqual(self.scope['cohort'],[QA_INTEGRATION])
        self.assertEqual(self.scope['selected_integration']['username'],'chota_test_4343434_bot')
        self.assertEqual(self.scope['selected_integration']['bot_id'],'8778392344')
        self.assertEqual(self.scope['principals'][:2],[
            dict(principal_id='main-telegram-qa-api',role='TELEGRAM',grants=[GRANT]),
            dict(principal_id='main-telegram-qa-processing',role='TELEGRAM_PROCESSING',grants=[GRANT]),
        ])
        self.assertEqual(self.scope['principals'][2],dict(
            principal_id='main-telegram-qa-managed-ai',caller='conversation-service',
            execution_namespace='main-chota.conversation.v1',grants=[dict(
                owner_id=OWNER,integration_id=QA_INTEGRATION,channel='TELEGRAM',
                agent_id=AGENT,agent_owner_id=OWNER)]))
        self.assertNotIn('*',json.dumps(self.scope['principals']))

    def test_gateway_recreate_single_replica_and_dedicated_token(self):
        gateway=resource(self.gateway,'Deployment','telegram-gateway-service')
        self.assertEqual(gateway['spec']['replicas'],1)
        self.assertEqual(gateway['spec']['strategy'],{'type':'Recreate'})
        self.assertEqual(reference(self.gateway,'telegram-gateway-service','CONVERSATION_SERVICE_TOKEN'),
                         dict(name='telegram-conversation-s2s-secret',key='CONVERSATION_SERVICE_TOKEN'))
        self.assertEqual(reference(self.gateway,'telegram-gateway-service','CHAT_S2S_TOKEN'),
                         dict(name='chat-s2s-secret',key='CHAT_S2S_TOKEN',optional=True))
        self.assertEqual(resource(self.gateway,'SealedSecret','telegram-conversation-s2s-secret')['secret_key_names'],
                         {'CONVERSATION_SERVICE_TOKEN'})

    def test_worker_uses_telegram_only_registries_and_has_no_provider_credentials(self):
        deployment='conversation-service-telegram-worker'
        self.assertEqual(reference(self.conversation,deployment,'CONVERSATION_AUTH_PRINCIPALS'),
                         dict(name='conversation-telegram-processing-secret',key='PROCESSING_AUTH_PRINCIPALS'))
        self.assertEqual(reference(self.conversation,deployment,'MANAGED_AI_BINDINGS'),
                         dict(name='conversation-telegram-managed-ai-secret',key='MANAGED_AI_BINDINGS'))
        env=environment(self.conversation,container(self.conversation,deployment))
        self.assertEqual(env['TELEGRAM_WORKER_PRINCIPAL_ID'],'main-telegram-qa-processing')
        self.assertEqual(env['TELEGRAM_WORKER_LEASE_SECONDS'],'30')
        self.assertEqual(env['TELEGRAM_WORKER_POLL_SECONDS'],'1')
        self.assertEqual(env['TELEGRAM_WORKER_HEALTH_PORT'],'8002')
        self.assertNotIn('BOT_TOKEN',env)
        self.assertEqual(env['MANAGED_AI_BASE_URL'],'http://ai-agent-service:8000')

    def test_api_and_ai_keep_existing_consumer_keys_and_ai_gets_registry_rollout(self):
        self.assertEqual(reference(self.conversation,'conversation-service','CONVERSATION_AUTH_PRINCIPALS'),
                         dict(name='conversation-principals-secret',key='API_AUTH_PRINCIPALS'))
        self.assertEqual(reference(self.conversation,'conversation-service','MANAGED_AI_BINDINGS'),
                         dict(name='conversation-beauty-managed-secret',key='MANAGED_AI_BINDINGS'))
        self.assertEqual(reference(self.ai,'ai-agent-service','MANAGED_AI_AUTH_PRINCIPALS'),
                         dict(name='ai-beauty-managed-secret',key='MANAGED_AI_AUTH_PRINCIPALS'))
        pod=resource(self.ai,'Deployment','ai-agent-service')['spec']['template']
        self.assertEqual(pod['metadata']['annotations']['goal4b.chota.by/managed-registry'],
                         'exact-telegram-qa-9b43e8ab-v1')
        self.assertNotIn('TURN_SETTLING_POLICIES',environment(self.ai,container(self.ai,'ai-agent-service')))

    def test_registry_extensions_preserve_every_prior_ciphertext_and_metadata_field(self):
        for item in self.scope['opaque_registry_extension']:
            with self.subTest(path=item['path']):
                before=original(item['path'])
                after=json.loads((REPO/item['path']).read_text())
                self.assertEqual(after['spec']['encryptedData'].keys(),
                                 before['spec']['encryptedData'].keys() | {item['new_key']})
                for key,value in before['spec']['encryptedData'].items():
                    self.assertTrue(after['spec']['encryptedData'][key]==value,'Prior ciphertext changed')
                expected='{{ concat (mustFromJson (index . "'+item['compiled_key']+'")) '
                expected+='(mustFromJson (index . "'+item['new_key']+'")) | mustToJson }}'
                self.assertEqual(after['spec']['template']['data'],{item['compiled_key']:expected})
                restored=copy.deepcopy(after)
                del restored['spec']['encryptedData'][item['new_key']]
                del restored['spec']['template']['data']
                del restored['spec']['template']['metadata']['annotations']['goal4b.chota.by/canary-integration']
                self.assertTrue(restored==before,'Unrelated sealed-resource field changed')

    def test_website_worker_retains_its_configuration_and_registry_references(self):
        website=resource(self.conversation,'Deployment','conversation-service-worker')
        self.assertEqual(website['spec']['replicas'],1)
        env=environment(self.conversation,container(self.conversation,'conversation-service-worker'))
        self.assertEqual(env['WEBSITE_WORKER_ENABLED'],'true')
        self.assertEqual(env['WEBSITE_WORKER_PRINCIPAL_ID'],'main-website-immediate-worker')
        self.assertEqual(reference(self.conversation,'conversation-service-worker','CONVERSATION_AUTH_PRINCIPALS'),
                         dict(name='conversation-principals-secret',key='PROCESSING_AUTH_PRINCIPALS'))
        # Controlled Handoff preparation now isolates this worker to the exact
        # retained Website binding; the API retains the combined registry.
        self.assertEqual(reference(self.conversation,'conversation-service-worker','MANAGED_AI_BINDINGS'),
                         dict(name='conversation-website-worker-managed-secret',key='MANAGED_AI_BINDINGS'))

    def test_cohort_rollback_retains_bindings_credentials_and_compatible_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for service in ('conversation-service','telegram-gateway-service'):
                shutil.copytree(REPO/'services'/service,root/'services'/service)
                path=root/'services'/service/'prod/config.properties'
                lines=path.read_text().splitlines()
                lines=['TELEGRAM_CANARY_INTEGRATION_IDS=[]' if line.startswith(
                    'TELEGRAM_CANARY_INTEGRATION_IDS=') else line for line in lines]
                path.write_text('\n'.join(lines)+'\n')
            for service,before in (('conversation-service',self.conversation),
                                   ('telegram-gateway-service',self.gateway)):
                p=subprocess.run(['kubectl','kustomize',str(root/'services'/service/'prod')],
                                 capture_output=True,text=True,check=True)
                after=[d for d in yaml.safe_load_all(p.stdout) if d]
                deploy='conversation-service' if service=='conversation-service' else 'telegram-gateway-service'
                # ConfigMap hash changes on rollback. Resolve using the rollback maps.
                rollback_maps={d['metadata']['name']:d.get('data',{}) for d in after if d['kind']=='ConfigMap'}
                runtime=container(after,deploy)
                values={}
                for source in runtime.get('envFrom',[]):
                    if 'configMapRef' in source:
                        values.update(rollback_maps[source['configMapRef']['name']])
                self.assertEqual(json.loads(values['TELEGRAM_CANARY_INTEGRATION_IDS']),[])
                if service=='telegram-gateway-service':
                    self.assertEqual(json.loads(values['TELEGRAM_MANAGED_BINDINGS']),[QA_BINDING])
                for d in after:
                    if d['kind']=='Deployment':
                        old=resource(before,'Deployment',d['metadata']['name'])
                        self.assertEqual(d['spec']['replicas'],old['spec']['replicas'])
                        for new_c,old_c in zip(d['spec']['template']['spec']['containers'],
                                               old['spec']['template']['spec']['containers']):
                            self.assertEqual(new_c['image'],old_c['image'])
                            self.assertEqual(new_c.get('env'),old_c.get('env'))
                # Credentials and templates are byte-for-byte unaffected in the
                # supported first rollback; retained MANAGED work can still drain.
                for path in (REPO/'services'/service/'prod').glob('*sealed-secret*'):
                    other=root/'services'/service/'prod'/path.name
                    self.assertTrue(other.read_bytes()==path.read_bytes())

if __name__=='__main__':
    unittest.main()
