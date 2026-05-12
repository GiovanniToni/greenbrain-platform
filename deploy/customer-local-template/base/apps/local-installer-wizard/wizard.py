#!/usr/bin/env python3
import http.server
import json
import os
import subprocess
import threading
import webbrowser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PORT = int(os.environ.get("GREENBRAIN_INSTALLER_WIZARD_PORT", "8099"))
PORT = DEFAULT_PORT
LOG_FILE = ROOT / "overlay" / "logs" / "installer_wizard.log"

install_process = None
install_lock = threading.Lock()

HTML = r"""<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <title>GreenBrain Installer</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #f3f7f2; color: #17351f; }
    .wrap { max-width: 880px; margin: 40px auto; background: white; border-radius: 18px; padding: 32px; box-shadow: 0 8px 30px rgba(0,0,0,.12); }
    .brand { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
    .logoBox {
      width: 64px;
      height: 64px;
      border-radius: 18px;
      background: #1f7a3b;
      display:flex;
      align-items:center;
      justify-content:center;
      flex-shrink:0;
      box-shadow: 0 4px 12px rgba(31,122,59,.28);
    }

    .logoBox svg {
      width: 34px;
      height: 34px;
      color: white;
    }
    h1 { margin: 0; font-size: 30px; }
    .step { display: none; }
    .step.active { display: block; }
    label { display:block; margin-top: 14px; font-weight: bold; }
    input, select { width: 100%; padding: 12px; margin-top: 6px; border: 1px solid #cfd8cf; border-radius: 10px; font-size: 15px; }
    button { border: 0; border-radius: 10px; padding: 12px 18px; margin: 18px 8px 0 0; font-weight: bold; cursor: pointer; }
    .primary { background: #1f7a3b; color: white; }
    .secondary { background: #e8efe8; color: #17351f; }
    .danger { background: #b42318; color: white; }
    pre { background: #111; color: #d7ffd7; padding: 16px; border-radius: 12px; min-height: 220px; overflow: auto; white-space: pre-wrap; }
    .hint { color: #5a6b5e; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="brand">
      <div class="logoBox">
        <svg xmlns="http://www.w3.org/2000/svg"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor"
             stroke-width="2">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                d="M11 20A7 7 0 0 1 4 13C4 7 9 4 20 4c0 11-3 16-9 16Zm0 0v-7m0 0c0-2 2-4 5-4"/>
        </svg>
      </div>
      <div>
        <h1>GreenBrain</h1>
        <div class="hint">Customer Local Installer</div>
      </div>
    </div>

    <div id="s1" class="step active">
      <h2>Benvenuto</h2>
      <p class="hint">Questo wizard installerà GreenBrain sul computer locale del cliente.</p>
      <button class="primary" onclick="go(2)">Inizia</button>
    </div>

    <div id="s2" class="step">
      <h2>Dati cliente</h2>
      <label>Tenant code</label><input id="tenant_code" value="cliente_reale">
      <label>Tenant name</label><input id="tenant_name" value="Cliente Reale">
      <label>Host pubblico</label><input id="tenant_host" value="cliente-reale.greenbrain.it">
      <button class="secondary" onclick="go(1)">Indietro</button>
      <button class="primary" onclick="go(3)">Avanti</button>
    </div>

    <div id="s3" class="step">
      <h2>Database locale</h2>
      <label>Postgres DB</label><input id="postgres_db" value="greenbrain_cliente_reale">
      <label>Postgres user</label><input id="postgres_user" value="greenbrain_cliente_reale">
      <label>Postgres password</label><input id="postgres_password" value="CHANGE_ME_DB_PASSWORD">
      <label>Backend port</label><input id="backend_port" value="8008">
      <label>Frontend port</label><input id="frontend_port" value="8088">
      <button class="secondary" onclick="go(2)">Indietro</button>
      <button class="primary" onclick="go(4)">Avanti</button>
    </div>

    <div id="s4" class="step">
      <h2>Source DB</h2>
      <p class="hint">Per ora puoi saltare il collegamento SQL Server e configurarlo dopo.</p>
      <label>Configurare Source DB ora?</label>
      <select id="source_db"><option value="no">No, salta</option><option value="yes">Sì</option></select>
      <button class="secondary" onclick="go(3)">Indietro</button>
      <button class="primary" onclick="go(5)">Avanti</button>
    </div>

    <div id="s5" class="step">
      <h2>Installa</h2>
      <p class="hint">Premi Installa per avviare il processo. Il log apparirà qui sotto.</p>
      <button class="secondary" onclick="go(4)">Indietro</button>
      <button id="installBtn" class="primary" onclick="startInstall()">Installa</button>
      <button class="secondary" onclick="openGreenBrain()">Apri GreenBrain</button>
      <pre id="log">Pronto.</pre>
    </div>
  </div>

<script>
function go(n){
  document.querySelectorAll('.step').forEach(x => x.classList.remove('active'));
  document.getElementById('s'+n).classList.add('active');
}
function payload(){
  return {
    tenant_code: document.getElementById('tenant_code').value,
    tenant_name: document.getElementById('tenant_name').value,
    tenant_host: document.getElementById('tenant_host').value,
    postgres_db: document.getElementById('postgres_db').value,
    postgres_user: document.getElementById('postgres_user').value,
    postgres_password: document.getElementById('postgres_password').value,
    backend_port: document.getElementById('backend_port').value,
    frontend_port: document.getElementById('frontend_port').value,
    source_db: document.getElementById('source_db').value
  };
}
async function startInstall(){
  document.getElementById('log').textContent = 'Installazione avviata...\n';
  await fetch('/api/install', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload())});
  poll();
}
async function poll(){
  const r = await fetch('/api/log');
  document.getElementById('log').textContent = await r.text();
  setTimeout(poll, 1500);
}
function openGreenBrain(){
  window.open('http://127.0.0.1:' + document.getElementById('frontend_port').value, '_blank');
}
</script>
</body>
</html>
"""

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        return

    def _send(self, code, body, ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body if isinstance(body, bytes) else body.encode())

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self._send(200, HTML, "text/html")
        elif path == "/favicon.ico":
            ico = ROOT / "base" / "frontend-dist" / "favicon.ico"
            if ico.exists():
                self._send(200, ico.read_bytes(), "image/x-icon")
            else:
                self._send(404, "not found")
        elif path == "/api/log":
            self._send(200, LOG_FILE.read_text(errors="ignore") if LOG_FILE.exists() else "Nessun log.")
        else:
            self._send(404, "not found")

    def do_POST(self):
        global install_process
        if urlparse(self.path).path != "/api/install":
            self._send(404, "not found")
            return

        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0")) or 0) or "{}")
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        LOG_FILE.write_text("GreenBrain installer wizard started\n")

        answers = "\n".join([
            data.get("tenant_code", "cliente_reale"),
            data.get("tenant_name", "Cliente Reale"),
            data.get("tenant_host", "cliente-reale.greenbrain.it"),
            data.get("postgres_db", "greenbrain_cliente_reale"),
            data.get("postgres_user", "greenbrain_cliente_reale"),
            data.get("postgres_password", "CHANGE_ME_DB_PASSWORD"),
            data.get("backend_port", "8008"),
            data.get("frontend_port", "8088"),
            ""
        ])

        env = os.environ.copy()
        env["GREENBRAIN_CONFIGURE_SOURCE_DB"] = data.get("source_db", "no")
        env.setdefault("GREENBRAIN_PROVISIONING_TOKEN", "dev_test_token")

        def run():
            with LOG_FILE.open("a") as f:
                p = subprocess.Popen(
                    ["bash", "install.sh"],
                    cwd=str(ROOT),
                    stdin=subprocess.PIPE,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    text=True,
                    env=env,
                )
                p.communicate(answers)
                f.write(f"\nINSTALL_EXIT_CODE={p.returncode}\n")

        threading.Thread(target=run, daemon=True).start()
        self._send(200, "started")

def open_browser(url: str) -> None:
    for cmd in (["gio", "open", url], ["xdg-open", url], ["sensible-browser", url]):
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except Exception:
            pass
    try:
        webbrowser.open(url)
    except Exception:
        pass


def bind_server():
    global PORT
    for port in [DEFAULT_PORT, DEFAULT_PORT + 1, DEFAULT_PORT + 2, 8110]:
        try:
            server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
            PORT = port
            return server
        except OSError:
            continue
    raise RuntimeError("No available local wizard port")


def main():
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    server = bind_server()
    url = f"http://127.0.0.1:{PORT}"
    print(f"GreenBrain installer wizard: {url}")
    threading.Timer(1.0, lambda: open_browser(url)).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
