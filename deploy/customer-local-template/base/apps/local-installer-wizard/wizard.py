#!/usr/bin/env python3
import os, json, threading, subprocess, webbrowser, secrets as _sec
from pathlib import Path
from urllib.parse import urlparse
import http.server

ROOT = Path(__file__).resolve().parents[3]
LOG_FILE = ROOT / "overlay/logs/installer_wizard.log"
STATUS_FILE = ROOT / "overlay/logs/installer_wizard_status.json"
DEFAULT_PORT = int(os.environ.get("GREENBRAIN_INSTALLER_WIZARD_PORT", "8099"))


def _read_env_file(path):
    data = {}
    try:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return data


def _read_file(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def _write_customer_env_if_missing(data):
    """Scrive overlay/env/customer-local.env dal form wizard se non esiste già.
    Se il file esiste (bundle cloud personalizzato) non viene toccato."""
    env_path = ROOT / "overlay/env/customer-local.env"
    if env_path.exists():
        return
    example_path = ROOT / "env/customer-local.env.example"
    env_path.parent.mkdir(parents=True, exist_ok=True)
    tc = "".join(c if c.isalnum() or c == "_" else "_"
                 for c in data.get("tenant_code", "cliente").lower()).strip("_") or "cliente"
    tn = data.get("tenant_name", tc)
    th = data.get("tenant_host", f"{tc.replace('_','-')}.greenbrain.it")
    pg_db = data.get("postgres_db",   f"greenbrain_{tc}")
    pg_u  = data.get("postgres_user", f"greenbrain_{tc}")
    pg_p  = data.get("postgres_password", "").strip() or _sec.token_urlsafe(18)
    bp    = data.get("backend_port",  "8008")
    fp    = data.get("frontend_port", "8088")
    ce    = data.get("customer_email",    "").strip()
    cn    = data.get("customer_name",     tn).strip()
    cp    = data.get("customer_password", "").strip()
    jwt   = _sec.token_urlsafe(32)
    pm    = "temporary_password" if cp else "cloud_password"
    ov = {
        "APP_ENV": "client-local", "TENANT_CODE": tc, "TENANT_NAME": tn, "TENANT_HOST": th,
        "POSTGRES_HOST": "postgres", "POSTGRES_PORT": "5432",
        "POSTGRES_DB": pg_db, "POSTGRES_USER": pg_u, "POSTGRES_PASSWORD": pg_p,
        "POSTGRES_SSLMODE": "disable",
        "DATABASE_URL": f"postgresql://{pg_u}:{pg_p}@postgres:5432/{pg_db}",
        "JWT_SECRET": jwt, "JWT_EXPIRE_MINUTES": "60",
        "LOCAL_BACKEND_PORT": bp, "LOCAL_FRONTEND_PORT": fp,
        "CENTRAL_AUTH_URL": "https://www.greenbrain.it", "CENTRAL_TENANT_CODE": tc,
        "REMOTE_ACCESS_MODE": "reverse-tunnel", "TUNNEL_ENABLED": "true",
        "LOCAL_CUSTOMER_EMAIL": ce, "LOCAL_CUSTOMER_FULL_NAME": cn,
        "LOCAL_CUSTOMER_TEMP_PASSWORD": cp, "LOCAL_CUSTOMER_PASSWORD_HASH": "",
        "LOCAL_CUSTOMER_PASSWORD_MODE": pm, "LOCAL_CUSTOMER_TENANT_CODE": tc,
        "LOCAL_CUSTOMER_HOME_HOST": th, "LOCAL_CUSTOMER_HOME_PATH": "/dashboard",
        "LOCAL_CUSTOMER_USER_ROLE": "customer_admin",
    }
    q = lambda v: f'"{v}"' if (" " in str(v) or "#" in str(v)) else str(v)
    lines, seen = [], set()
    base = example_path.read_text().splitlines() if example_path.exists() else []
    for raw in base:
        if "=" in raw and not raw.lstrip().startswith("#"):
            k = raw.split("=", 1)[0].strip()
            if k in ov:
                lines.append(f"{k}={q(ov[k])}")
                seen.add(k)
            else:
                lines.append(raw)
        else:
            lines.append(raw)
    for k, v in ov.items():
        if k not in seen:
            lines.append(f"{k}={q(v)}")
    env_path.write_text("\n".join(lines) + "\n")


class WizardHandler(http.server.BaseHTTPRequestHandler):
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
            f = ROOT / "base/frontend-dist/wizard_index.html"
            if f.exists():
                self._send(200, f.read_bytes(), "text/html; charset=utf-8")
            else:
                self._send(200, b"<h1>GreenBrain Installer</h1><p>wizard_index.html not found</p>", "text/html")

        elif path == "/favicon.ico":
            ico = ROOT / "base/frontend-dist/favicon.ico"
            self._send(200, ico.read_bytes() if ico.exists() else b"", "image/x-icon")

        elif path == "/api/precompiled-info":
            env = _read_env_file(ROOT / "overlay/env/customer-local.env")
            tc = (env.get("TENANT_CODE") or env.get("LOCAL_CUSTOMER_TENANT_CODE") or env.get("CENTRAL_TENANT_CODE") or "")
            self._send(200, json.dumps({
                "is_personalized": bool(
                    env.get("LOCAL_CUSTOMER_EMAIL")
                    or (tc and tc.lower() not in ("", "cliente_reale"))
                ),
                "customer_email":    env.get("LOCAL_CUSTOMER_EMAIL", ""),
                "customer_name":     env.get("LOCAL_CUSTOMER_FULL_NAME") or env.get("TENANT_NAME", ""),
                "tenant_code":       tc,
                "tenant_name":       env.get("TENANT_NAME", ""),
                "postgres_db":       env.get("POSTGRES_DB", ""),
                "postgres_user":     env.get("POSTGRES_USER", ""),
                "postgres_password": env.get("POSTGRES_PASSWORD", ""),
                "backend_port":      env.get("LOCAL_BACKEND_PORT", "8008"),
                "frontend_port":     env.get("LOCAL_FRONTEND_PORT", "8088"),
                "version":           _read_file(ROOT / "VERSION").strip(),
            }), "application/json")

        elif path == "/api/local-credentials":
            env = _read_env_file(ROOT / "overlay/env/customer-local.env")
            self._send(200, json.dumps({
                "email":         env.get("LOCAL_CUSTOMER_EMAIL", ""),
                "password":      env.get("LOCAL_CUSTOMER_TEMP_PASSWORD", ""),
                "mode":          env.get("LOCAL_CUSTOMER_PASSWORD_MODE", ""),
                "tenant":        env.get("LOCAL_CUSTOMER_TENANT_CODE") or env.get("TENANT_CODE", ""),
                "customer_name": env.get("LOCAL_CUSTOMER_FULL_NAME") or env.get("TENANT_NAME", ""),
                "version":       _read_file(ROOT / "VERSION").strip(),
                "frontend_port": env.get("LOCAL_FRONTEND_PORT", "8088"),
            }), "application/json")

        elif path == "/api/log":
            self._send(200, LOG_FILE.read_text(errors="ignore") if LOG_FILE.exists() else "Nessun log.")

        elif path == "/api/status":
            self._send(200,
                       STATUS_FILE.read_text(errors="ignore") if STATUS_FILE.exists()
                       else json.dumps({"state": "idle"}),
                       "application/json")

        else:
            self._send(404, "not found")

    def do_POST(self):
        parsed = urlparse(self.path).path
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")) or 0)
        data = json.loads(body or "{}")

        if parsed == "/api/test-source-db":
            host = data.get("host", "").strip()
            port = str(data.get("port", 1433))
            if not host:
                self._send(200, json.dumps({"ok": False, "message": "Host mancante"}), "application/json")
                return
            try:
                r = subprocess.run(
                    ["bash", "-c", f"timeout 5 bash -c '</dev/tcp/{host}/{port}' 2>&1"],
                    capture_output=True, text=True, timeout=10,
                )
                ok = r.returncode == 0
                self._send(200, json.dumps({
                    "ok": ok,
                    "message": "Connessione TCP riuscita" if ok else f"Connessione fallita ({host}:{port})",
                }), "application/json")
            except Exception as exc:
                self._send(200, json.dumps({"ok": False, "message": str(exc)}), "application/json")
            return

        if parsed == "/api/save-source-db":
            p = ROOT / "overlay/env/source-db.env"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("\n".join([
                f"SOURCE_DB_HOST={data.get('host', '')}",
                f"SOURCE_DB_PORT={data.get('port', 1433)}",
                f"SOURCE_DB_DATABASE={data.get('database', '')}",
                f"SOURCE_DB_USER={data.get('username', '')}",
                f"SOURCE_DB_PASSWORD={data.get('password', '')}",
                "SOURCE_DB_DRIVER=ODBC Driver 18 for SQL Server",
            ]) + "\n")
            self._send(200, json.dumps({"ok": True}), "application/json")
            return

        if parsed != "/api/install":
            self._send(404, "not found")
            return

        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        LOG_FILE.write_text("GreenBrain installer wizard started\n", encoding="utf-8")
        STATUS_FILE.write_text(json.dumps({"state": "running", "exit_code": None}), encoding="utf-8")

        _write_customer_env_if_missing(data)

        force_fresh_install = bool(data.get("force_fresh_install"))

        env = os.environ.copy()
        env["GREENBRAIN_CONFIGURE_SOURCE_DB"] = "no"
        if force_fresh_install:
            env["GREENBRAIN_FORCE_FRESH_INSTALL"] = "1"
        rt = ROOT / "overlay/provisioning/local-runtime.env"
        if rt.exists():
            rv = _read_env_file(rt)
            if rv.get("PROVISIONING_TOKEN"):
                env["GREENBRAIN_PROVISIONING_TOKEN"] = rv["PROVISIONING_TOKEN"]
        env.setdefault("GREENBRAIN_PROVISIONING_TOKEN", "dev_wizard_token")

        def run():
            with LOG_FILE.open("a") as f:
                if force_fresh_install:
                    f.write("\nGREENBRAIN_FORCE_FRESH_INSTALL=1\n")
                    f.write("Fresh reset requested from installer wizard\n")
                    f.flush()
                p = subprocess.Popen(
                    ["bash", "install.sh"],
                    cwd=str(ROOT),
                    stdin=subprocess.DEVNULL,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    text=True,
                    env=env,
                )
                p.wait()
                f.write(f"\nINSTALL_EXIT_CODE={p.returncode}\n")
                f.flush()
                state = "completed" if p.returncode == 0 else "failed"
                STATUS_FILE.write_text(
                    json.dumps({"state": state, "exit_code": p.returncode}),
                    encoding="utf-8",
                )

        threading.Thread(target=run, daemon=True).start()
        self._send(200, "started")


def bind_server():
    for port in [DEFAULT_PORT, DEFAULT_PORT + 1, DEFAULT_PORT + 2, 8110]:
        try:
            return http.server.ThreadingHTTPServer(("0.0.0.0", port), WizardHandler), port
        except OSError:
            continue
    raise RuntimeError("No available wizard port")


def main():
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    server, port = bind_server()
    url = f"http://localhost:{port}"
    print(f"GreenBrain installer wizard: {url}")
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    server.serve_forever()


if __name__ == "__main__":
    main()