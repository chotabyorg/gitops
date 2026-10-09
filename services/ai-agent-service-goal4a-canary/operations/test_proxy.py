"""Exact nginx index artifact tests with synthetic loopback HTTP/TLS dependencies.

Guard config is unchanged. Relay fixture changes only reviewed target IP and test
CA path; fixed path, TLS verification, Host/SNI, headers and policy stay intact.
Only this test's labelled containers/files are created or removed.
"""

from datetime import datetime, timedelta, timezone
import http.client
import json
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import unittest
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SERVICE = Path(__file__).resolve().parents[1]
NGINX = "docker.io/library/nginx@sha256:8f029c543423e3eac6b08254718bc31eb75633b1e448026b6616927baa7d4bfe"
BACKEND = r'''
import http.server,json,ssl,threading
from pathlib import Path
events=Path('/evidence/events.jsonl')
lock=threading.Lock()
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self): self.handle_request()
 def do_POST(self): self.handle_request()
 def handle_request(self):
  body=self.rfile.read(int(self.headers.get('Content-Length','0')))
  with lock:
   with events.open('a') as f: f.write(json.dumps({'path':self.path,'method':self.command,'body':body.decode(),'headers':dict(self.headers),'sni':getattr(self.connection,'goal4a_sni',None)})+'\n')
  value=json.loads(body or '{}'); status=value.get('synthetic_status',200)
  self.send_response(status)
  self.send_header('Content-Type','application/json')
  if status in (301,302,307,308): self.send_header('Location','https://forbidden.invalid/'+value.get('sentinel',''))
  if value.get('accel'): self.send_header('X-Accel-Redirect','/forbidden/'+value.get('sentinel',''))
  self.end_headers(); self.wfile.write(b'{"synthetic":"ok"}')
plain=http.server.ThreadingHTTPServer(('0.0.0.0',8000),Handler)
tls=http.server.ThreadingHTTPServer(('0.0.0.0',443),Handler)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/fixtures/ca.crt','/fixtures/server.key')
context.set_servername_callback(lambda sock,name,ctx:setattr(sock,'goal4a_sni',name))
tls.socket=context.wrap_socket(tls.socket,server_side=True)
threading.Thread(target=plain.serve_forever,daemon=True).start(); tls.serve_forever()
'''


def docker(*args, check=True):
    result = subprocess.run(["docker", *args], capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError("OWNED_PROXY_TEST_CONTAINER_COMMAND_FAILED")
    return result.stdout + result.stderr if args and args[0] == "logs" else result.stdout


class ProxyArtifact(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="goal4a-proxy-tests-")
        cls.root = Path(cls.directory.name)
        cls.root.chmod(0o755)  # Production ConfigMap directories are traversable by nonroot.
        cls.evidence = cls.root / "evidence"
        cls.evidence.mkdir()
        cls.sentinel = "goal4a_private_synthetic_" + secrets.token_hex(24)
        key = rsa.generate_private_key(public_exponent=65537,key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,"openrouter.ai")])
        cert = x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.now(timezone.utc)-timedelta(days=1)).not_valid_after(datetime.now(timezone.utc)+timedelta(days=1)).add_extension(x509.SubjectAlternativeName([x509.DNSName("openrouter.ai")]),critical=False).add_extension(x509.BasicConstraints(ca=True,path_length=None),critical=True).sign(key,hashes.SHA256())
        (cls.root/"ca.crt").write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        (cls.root/"server.key").write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
        (cls.root/"backend.py").write_text(BACKEND)
        cls.name = "goal4a-proxy-test-"+uuid.uuid4().hex[:12]
        cls.backend = docker("run","--rm","-d","--name",cls.name,
            "--label","goal4a.test.owner="+cls.name,"-p","127.0.0.1::8080",
            "-v",str(cls.root)+":/fixtures:ro","-v",str(cls.evidence)+":/evidence",
            "python:3.11-slim-bookworm","python","-I","-B","/fixtures/backend.py").strip()
        cls.port = int(json.loads(docker("inspect",cls.backend))[0]["NetworkSettings"]["Ports"]["8080/tcp"][0]["HostPort"])
        cls.proxy = None
        cls.all_logs = ""

    @classmethod
    def tearDownClass(cls):
        if cls.proxy:
            cls.all_logs += docker("logs",cls.proxy,check=False)
            docker("rm","-f",cls.proxy,check=False)
        docker("rm","-f",cls.backend,check=False)
        cls.directory.cleanup()
        if cls.sentinel in cls.all_logs:
            raise AssertionError("SYNTHETIC_PAYLOAD_REACHED_NGINX_LOGS")

    def events(self):
        path = self.evidence/"events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def start(self, config):
        if self.__class__.proxy:
            self.__class__.all_logs += docker("logs",self.__class__.proxy,check=False)
            docker("rm","-f",self.__class__.proxy)
        (self.root/"nginx.conf").write_text(config)
        self.__class__.proxy = docker("run","--rm","-d","--name",self.name+"-nginx",
            "--label","goal4a.test.owner="+self.name,"--network","container:"+self.backend,
            "--user","10001:10001","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges",
            "--tmpfs","/tmp:rw,nosuid,nodev,size=8388608,uid=10001,gid=10001",
            "-v",str(self.root)+":/fixtures:ro",NGINX,"nginx","-c","/fixtures/nginx.conf","-g","daemon off;").strip()
        for _ in range(100):
            try:
                if self.request("GET","/health")[0]==200:
                    return
            except (OSError,http.client.HTTPException):
                pass
            time.sleep(.05)
        raise RuntimeError("OWNED_PROXY_TEST_STARTUP_FAILED")

    def request(self, method, path, payload=None):
        conn=http.client.HTTPConnection("127.0.0.1",self.port,timeout=3)
        body=json.dumps(payload or {"sentinel":self.sentinel})
        conn.request(method,path,body=body,headers={"Authorization":"Bearer "+self.sentinel,
            "X-Service-Token":self.sentinel,"X-Request-ID":self.sentinel,"Cookie":self.sentinel,
            "Content-Type":"application/json"})
        response=conn.getresponse(); result=(response.status,response.read(),dict(response.getheaders()))
        conn.close(); return result

    def test_guard_exact_routes_methods_aliases_and_no_sensitive_logs(self):
        self.start((SERVICE/"release/guard.conf").read_text())
        base=len(self.events())
        for path in ("/internal/v1/managed-turns/execute","/internal/v1/managed-turns/evidence"):
            self.assertEqual(self.request("POST",path)[0],200)
        events=self.events()[base:]
        self.assertEqual(len(events),2)
        self.assertTrue(all(e["headers"].get("X-Service-Token")==self.sentinel for e in events))
        self.assertTrue(all("Authorization" not in e["headers"] and "Cookie" not in e["headers"] and
                            "X-Request-ID" not in e["headers"] for e in events))
        before=len(self.events())
        for method,path in (("POST","/v1/chat/completions"),("GET","/v1/agents"),
            ("GET","/v1/openrouter-key"),("GET","/internal/v1/managed-turns/execute"),
            ("HEAD","/health"),("POST","/health"),("CONNECT","openrouter.ai:443"),
            ("POST","/internal/v1/managed-turns/execute?key="+self.sentinel),
            ("POST","/internal/v1/managed-turns/execute/"),
            ("POST","/internal/v1/managed-turns/%65xecute"),
            ("POST","/internal/v1//managed-turns/execute"),
            ("POST","/internal/v1/a/../managed-turns/execute"),
            ("POST","/%zz"+self.sentinel)):
            self.assertIn(self.request(method,path)[0],(400,404,405))
        self.assertEqual(len(self.events()),before)
        self.assertNotIn(self.sentinel,docker("logs",self.__class__.proxy,check=False))

    def test_relay_fixed_tls_target_no_redirect_accel_retry_or_sensitive_logs(self):
        template=(SERVICE/"release/relay.conf.template").read_text()
        config=template.replace("${OPENROUTER_IPV4}","127.0.0.1").replace(
            "/etc/ssl/certs/ca-certificates.crt","/fixtures/ca.crt")
        self.start(config)
        before=len(self.events())
        self.assertEqual(self.request("POST","/api/v1/chat/completions")[0],200)
        for status in (301,302,307,308):
            response=self.request("POST","/api/v1/chat/completions",{"synthetic_status":status,"sentinel":self.sentinel})
            self.assertEqual(response[0],502)
            self.assertNotIn("Location",response[2])
            self.assertNotIn(self.sentinel.encode(),response[1])
        self.assertEqual(self.request("POST","/api/v1/chat/completions",{"accel":True,"sentinel":self.sentinel})[0],200)
        self.assertEqual(self.request("POST","/api/v1/chat/completions",{"synthetic_status":500})[0],500)
        events=self.events()[before:]
        self.assertEqual(len(events),7)  # One upstream attempt for each request, no follow.
        for event in events:
            self.assertEqual(event["path"],"/api/v1/chat/completions")
            self.assertEqual(event["headers"]["Host"],"openrouter.ai")
            self.assertEqual(event["sni"],"openrouter.ai")
            self.assertEqual(event["headers"]["Authorization"],"Bearer "+self.sentinel)
            self.assertNotIn("Cookie",event["headers"])
        before=len(self.events())
        for method,path in (("GET","/api/v1/chat/completions"),("CONNECT","forbidden.invalid:443"),
                ("POST","/api/v1/chat/completions?target="+self.sentinel),
                ("POST","/api/v1//chat/completions"),("POST","/api/v1/chat/%63ompletions"),
                ("POST","/api/v1/chat/completions/"),("POST","/v1/chat/completions"),
                ("HEAD","/health")):
            self.assertIn(self.request(method,path)[0],(400,404,405))
        self.assertEqual(len(self.events()),before)
        logs=docker("logs",self.__class__.proxy,check=False)
        self.assertNotIn(self.sentinel,logs)
        records=[json.loads(line) for line in logs.splitlines() if line.startswith('{')]
        upstream=[r for r in records if r["upstream_status"] not in ("","-")]
        self.assertEqual(len(upstream),7)
        self.assertTrue(all(set(r)=={"event","request_id","status","upstream_status","upstream_addr","request_time"} for r in records))
        self.assertTrue(all(len(r["request_id"])==32 and r["request_id"]!=self.sentinel for r in records))

    def test_relay_hostname_verification_fails_without_http_dispatch(self):
        config=(SERVICE/"release/relay.conf.template").read_text().replace("${OPENROUTER_IPV4}","127.0.0.1").replace(
            "/etc/ssl/certs/ca-certificates.crt","/fixtures/ca.crt").replace(
            "proxy_ssl_name openrouter.ai;","proxy_ssl_name forbidden.invalid;")
        self.start(config)
        before=len(self.events())
        self.assertEqual(self.request("POST","/api/v1/chat/completions")[0],502)
        self.assertEqual(len(self.events()),before)
        self.assertNotIn(self.sentinel,docker("logs",self.__class__.proxy,check=False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
