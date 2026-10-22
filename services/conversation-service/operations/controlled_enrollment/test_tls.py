"""Real pinned NGINX with disposable CA/leaf and local deterministic HTTP peer."""
import datetime,http.client,json,pathlib,socket,ssl,subprocess,tempfile,time,unittest,urllib.request,uuid
from cryptography import x509
from cryptography.x509.oid import NameOID,ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
HERE=pathlib.Path(__file__).resolve().parent
IMAGE='docker.io/library/nginx@sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe'
PEER='conversation-service.prod.svc.cluster.local'
def run(*args):return subprocess.check_output(['docker',*args],text=True,stderr=subprocess.PIPE).strip()
class TLS(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.p=pathlib.Path(cls.tmp.name);cls.names=[]
  now=datetime.datetime.now(datetime.timezone.utc);ca=rsa.generate_private_key(public_exponent=65537,key_size=2048);name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'disposable-test-ca')])
  cert=x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(ca.public_key()).serial_number(1).not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=1)).add_extension(x509.BasicConstraints(ca=True,path_length=0),True).sign(ca,hashes.SHA256())
  (cls.p/'ca.crt').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
  for variant,until in [('valid',now+datetime.timedelta(hours=1)),('expired',now-datetime.timedelta(hours=1))]:
   d=cls.p/variant;d.mkdir();key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
   leaf=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,PEER)])).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(hours=2)).not_valid_after(until).add_extension(x509.SubjectAlternativeName([x509.DNSName(PEER)]),False).add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),False).sign(ca,hashes.SHA256())
   (d/'tls.crt').write_bytes(leaf.public_bytes(serialization.Encoding.PEM));(d/'tls.key').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
  cls.peer='prereq-peer-'+uuid.uuid4().hex[:8];cls.names.append(cls.peer)
  run('run','-d','--name',cls.peer,'-p','127.0.0.1::8443','-p','127.0.0.1::8000','-v',str(HERE/'peer.py')+':/peer.py:ro','python:3.12-slim','python','/peer.py')
  cls.port=int(run('port',cls.peer,'8443').split(':')[-1]);cls.upstream=int(run('port',cls.peer,'8000').split(':')[-1]);cls.start_proxy('valid')
 @classmethod
 def start_proxy(cls,variant):
  if hasattr(cls,'proxy'):run('rm','-f',cls.proxy)
  cls.proxy='prereq-nginx-'+uuid.uuid4().hex[:8];cls.names.append(cls.proxy)
  config=HERE.parents[1]/'prod/website-transport/nginx.conf'
  run('run','-d','--platform','linux/amd64','--name',cls.proxy,'--network','container:'+cls.peer,'--user','10001:10001','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--tmpfs','/tmp:rw,noexec,nosuid,size=8m','-v',str(config)+':/etc/website-proxy/nginx.conf:ro','-v',str(cls.p/variant)+':/etc/website-tls:ro',IMAGE,'nginx','-c','/etc/website-proxy/nginx.conf','-g','daemon off;')
  for _ in range(50):
   try:
    run('exec',cls.proxy,'curl','--silent','--fail','http://127.0.0.1:18083/healthz');return
   except subprocess.CalledProcessError:time.sleep(.1)
  raise RuntimeError('local nginx failed readiness')
 @classmethod
 def tearDownClass(cls):
  for n in reversed(cls.names):
   subprocess.run(['docker','rm','-f',n],capture_output=True)
  cls.tmp.cleanup()
 def request(self,body='ok',path='/internal/v1/website/sessions',token='SYNTHETIC_SECRET_SENTINEL',name=PEER,trust=True,timeout=3):
  context=ssl.create_default_context(cafile=str(self.p/'ca.crt')) if trust else ssl.create_default_context()
  sock=context.wrap_socket(socket.create_connection(('127.0.0.1',self.port),timeout=timeout),server_hostname=name)
  headers={'Host':PEER,'Content-Length':str(len(body)),'X-Service-Token':token,'Authorization':'SYNTHETIC_SECRET_SENTINEL','Cookie':'SYNTHETIC_SECRET_SENTINEL','Connection':'close'}
  sock.sendall(('POST '+path+' HTTP/1.1\r\n'+''.join(k+': '+v+'\r\n' for k,v in headers.items())+'\r\n'+body).encode())
  try:
   response=http.client.HTTPResponse(sock);response.begin();return response.status,dict(response.getheaders()),response.read()
  finally:sock.close()
 def test_valid_chain_name_status_no_store(self):
  status,headers,_=self.request();self.assertEqual(status,201);self.assertEqual(headers['Cache-Control'],'no-store')
 def test_wrong_ca_and_name(self):
  for kwargs in [{'trust':False},{'name':'other.internal'}]:
   with self.subTest(kwargs=kwargs),self.assertRaises(ssl.SSLCertVerificationError):self.request(**kwargs)
 def test_bad_missing_credential(self):
  for token in ['', 'wrong']:
   status,headers,_=self.request(token=token);self.assertEqual(status,401);self.assertEqual(headers['Cache-Control'],'no-store')
 def test_non_session_paths_no_dispatch(self):
  for path in ['/internal/v1/inbox-grants/provision','/internal/v1/website/sessions/not-allowed','/health']:
   self.assertEqual(self.request(path=path)[0],404)
 def test_lost_response_and_timeout_dispatch_once(self):
  self.assertEqual(self.request(body='lost')[0],502)
  with self.assertRaises((TimeoutError,socket.timeout)):self.request(body='slow',timeout=.1)
  time.sleep(.6)
  counts=json.load(urllib.request.urlopen('http://127.0.0.1:'+str(self.upstream)))
  self.assertEqual(counts['lost'],1);self.assertEqual(counts['slow'],1)
 def test_z_expired_certificate_and_logs(self):
  for container in [self.peer,self.proxy]:
   logs=subprocess.run(['docker','logs',container],capture_output=True,text=True,check=True)
   self.assertNotIn('SYNTHETIC_SECRET_SENTINEL',logs.stdout+logs.stderr)
  self.start_proxy('expired')
  with self.assertRaises(ssl.SSLCertVerificationError):self.request()
if __name__=='__main__':unittest.main(verbosity=2)
