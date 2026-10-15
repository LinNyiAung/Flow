"""Serves ONLY the captured e-mail outbox (outbox.jsonl) at http://127.0.0.1:8766/outbox
so integration tests on the emulator (http://10.0.2.2:8766/outbox) can read verification
links / OTP codes. Local-only test helper."""
import http.server, os, sys
OUTBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "outbox.jsonl")

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] != "/outbox":
            self.send_response(404); self.end_headers(); return
        try:
            data = open(OUTBOX, "rb").read()
        except FileNotFoundError:
            data = b""
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", 8766), H).serve_forever()
