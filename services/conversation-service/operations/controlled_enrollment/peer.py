"""Disposable deterministic transport peer. No external I/O and no request logging."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json,time
counts={}
class Peer(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  raw=json.dumps(counts).encode();self.send_response(200);self.end_headers();self.wfile.write(raw)
 def do_POST(self):
  body=self.rfile.read(int(self.headers.get('Content-Length','0'))).decode()
  counts[body]=counts.get(body,0)+1
  if body=='lost':self.connection.close();return
  if body=='slow':time.sleep(.5)
  status=201 if self.headers.get('X-Service-Token')=='SYNTHETIC_SECRET_SENTINEL' else 401
  if self.headers.get('Authorization') or self.headers.get('Cookie'):status=500
  self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.end_headers()
  try:self.wfile.write(b'{"fixture":true}')
  except (BrokenPipeError,ConnectionResetError):pass
ThreadingHTTPServer(('0.0.0.0',8000),Peer).serve_forever()
