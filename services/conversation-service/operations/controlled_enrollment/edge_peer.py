"""Synthetic Gateway status/forwarded-header peer; never forwards outside Docker."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
class Peer(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):self.reply()
 def do_POST(self):self.reply()
 def reply(self):
  self.send_response(200 if self.headers.get('Authorization')=='synthetic-owner' else 401)
  self.send_header('Content-Type','application/json');self.end_headers()
  self.wfile.write(json.dumps({'path':self.path,'method':self.command,'proto':self.headers.get('X-Forwarded-Proto'),'real_ip':self.headers.get('X-Real-Ip')}).encode())
ThreadingHTTPServer(('0.0.0.0',8000),Peer).serve_forever()
