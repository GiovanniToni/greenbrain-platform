#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Uso: build_customer_local_universal_installer.sh <version>}"
ROOT="/opt/greenbrain-platform"
REL="$ROOT/releases/customer-local/$VERSION"
TAR="$REL/customer-local-$VERSION.tar.gz"
OUT_DIR="$REL/universal-installer"
ZIP="$REL/GreenBrain-Installer.zip"

[ -f "$TAR" ] || { echo "ERRORE: manca $TAR"; exit 1; }

rm -rf "$OUT_DIR" "$ZIP"
mkdir -p "$OUT_DIR"

make_script() {
  local out="$1"
  local title="$2"

  cat > "$out" <<HEADER
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="\${HOME}/GreenBrain-Customer-Local"
mkdir -p "\$APP_DIR"

echo "======================================"
echo "   $title"
echo "======================================"
echo
echo "Estraggo GreenBrain in:"
echo "  \$APP_DIR"
echo

ARCHIVE_LINE=\$(awk '/^__GREENBRAIN_ARCHIVE_BELOW__$/ {print NR + 1; exit 0;}' "\$0")
tail -n +"\$ARCHIVE_LINE" "\$0" | tar -xz -C "\$APP_DIR" --strip-components=1

cd "\$APP_DIR/customer-local-template" 2>/dev/null || cd "\$APP_DIR"

chmod +x INSTALL_GREENBRAIN.sh install.sh 2>/dev/null || true

echo
echo "Avvio wizard GreenBrain..."
echo

exec bash ./INSTALL_GREENBRAIN.sh

exit 0
__GREENBRAIN_ARCHIVE_BELOW__
HEADER

  cat "$TAR" >> "$out"
  chmod +x "$out"
}

make_script "$OUT_DIR/INSTALLA_GREENBRAIN_LINUX.run" "GreenBrain Installer Linux"
make_script "$OUT_DIR/INSTALLA_GREENBRAIN_MAC.command" "GreenBrain Installer macOS"

cat > "$OUT_DIR/INSTALLA_GREENBRAIN_WINDOWS.bat" <<'BAT'
@echo off
setlocal

title GreenBrain Installer Windows

echo ======================================
echo    GreenBrain Installer Windows
echo ======================================
echo.

where powershell >nul 2>nul
if errorlevel 1 (
  echo ERRORE: PowerShell non trovato.
  pause
  exit /b 1
)

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0INSTALLA_GREENBRAIN_WINDOWS.ps1"

echo.
pause
BAT

cat > "$OUT_DIR/INSTALLA_GREENBRAIN_WINDOWS.ps1" <<'PS1'
$ErrorActionPreference = "Stop"

Write-Host "======================================"
Write-Host "   GreenBrain Installer Windows"
Write-Host "======================================"
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Open-Url($url) {
  Start-Process $url | Out-Null
}

function Test-Command($cmd) {
  $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

Write-Host "Controllo WSL..."
if (-not (Test-Command "wsl.exe")) {
  Write-Host ""
  Write-Host "WSL non risulta installato."
  Write-Host "Provo ad avviare installazione WSL..."
  Write-Host ""
  try {
    Start-Process -FilePath "wsl.exe" -ArgumentList "--install" -Verb RunAs -Wait
    Write-Host ""
    Write-Host "Se Windows richiede riavvio, riavvia il PC e rilancia questo file."
  } catch {
    Write-Host "Non sono riuscito ad avviare automaticamente l'installazione WSL."
    Write-Host "Apro la guida Microsoft."
    Open-Url "https://learn.microsoft.com/windows/wsl/install"
  }
  exit 1
}

Write-Host "WSL trovato."

Write-Host ""
Write-Host "Controllo Docker Desktop..."
$dockerOk = $false
try {
  docker info *> $null
  $dockerOk = $true
} catch {
  $dockerOk = $false
}

if (-not $dockerOk) {
  $dockerDesktopPaths = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "$env:LocalAppData\Docker\Docker Desktop.exe"
  )

  $dockerDesktop = $dockerDesktopPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

  if ($dockerDesktop) {
    Write-Host "Docker Desktop trovato. Lo avvio..."
    Start-Process $dockerDesktop | Out-Null
  } else {
    Write-Host ""
    Write-Host "Docker Desktop non trovato."
    Write-Host "GreenBrain richiede Docker Desktop per eseguire database, backend, frontend e ML locali."
    Write-Host "Apro la pagina ufficiale Docker Desktop."
    Open-Url "https://www.docker.com/products/docker-desktop/"
    Write-Host ""
    Write-Host "Dopo l'installazione:"
    Write-Host "1) apri Docker Desktop"
    Write-Host "2) attendi che Docker Engine sia avviato"
    Write-Host "3) rilancia INSTALLA_GREENBRAIN_WINDOWS.bat"
    exit 1
  }

  Write-Host "Attendo Docker Engine..."
  for ($i = 1; $i -le 180; $i++) {
    try {
      docker info *> $null
      $dockerOk = $true
      break
    } catch {
      if ($i % 15 -eq 0) {
        Write-Host "Attendo Docker Desktop... ($i/180)"
      }
      Start-Sleep -Seconds 2
    }
  }
}

if (-not $dockerOk) {
  Write-Host ""
  Write-Host "ERRORE: Docker Desktop è aperto ma Docker Engine non è ancora pronto."
  Write-Host "Aspetta che Docker Desktop mostri Engine running, poi rilancia questo file."
  exit 1
}

Write-Host "Docker pronto."

Write-Host ""
Write-Host "Cerco una distro WSL Linux con bash..."

$usableDistro = $null
$distros = @(wsl -l -q 2>$null) | ForEach-Object { ($_ -replace "\0","").Trim() } | Where-Object { $_ -ne "" }

foreach ($d in $distros) {
  if ($d -match "docker-desktop") { continue }
  wsl -d "$d" -- bash -lc "command -v bash >/dev/null 2>&1" *> $null
  if ($LASTEXITCODE -eq 0) {
    $usableDistro = $d
    break
  }
}

if (-not $usableDistro) {
  Write-Host ""
  Write-Host "Nessuna distro WSL con bash trovata."
  Write-Host "Installo Ubuntu tramite WSL..."
  Write-Host ""
  Start-Process -FilePath "wsl.exe" -ArgumentList "--install -d Ubuntu" -Verb RunAs -Wait
  Write-Host ""
  Write-Host "Se Windows richiede riavvio, riavvia il PC."
  Write-Host "Poi apri Ubuntu una prima volta dal menu Start e rilancia INSTALLA_GREENBRAIN_WINDOWS.bat."
  exit 1
}

Write-Host "Distro WSL selezionata: $usableDistro"

$wslDir = (wsl -d "$usableDistro" -- wslpath -a "$ScriptDir").Trim()

Write-Host ""
Write-Host "Avvio GreenBrain tramite WSL..."
wsl -d "$usableDistro" -- bash -lc "cd '$wslDir' && chmod +x INSTALLA_GREENBRAIN_LINUX.run && ./INSTALLA_GREENBRAIN_LINUX.run"

if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "ERRORE: installazione GreenBrain non completata."
  Write-Host "Codice errore: $LASTEXITCODE"
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Installazione GreenBrain completata."
PS1

if [ -f "$ROOT/deploy/customer-local-template/GreenBrain-Install.desktop" ]; then
  cp "$ROOT/deploy/customer-local-template/GreenBrain-Install.desktop" "$OUT_DIR/GreenBrain-Install.desktop"
  chmod +x "$OUT_DIR/GreenBrain-Install.desktop"
fi

cat > "$OUT_DIR/LEGGIMI_INSTALLAZIONE.txt" <<TXT
GREENBRAIN INSTALLER

Scegli il file in base al tuo sistema operativo.

WINDOWS
1) Doppio click su:
   INSTALLA_GREENBRAIN_WINDOWS.bat

2) Se Windows chiede conferma, premi Esegui / Sì.

3) Se WSL o Docker Desktop non sono installati, l'installer apre la guida corretta.
   Dopo installazione/riavvio, rilancia INSTALLA_GREENBRAIN_WINDOWS.bat.

MAC
1) Doppio click su:
   INSTALLA_GREENBRAIN_MAC.command

2) Se macOS blocca il file:
   tasto destro sul file > Apri > Apri.

3) Se Docker Desktop non è installato, l'installer apre la pagina Docker.
   Dopo installazione, apri Docker Desktop e rilancia il file.

LINUX
Metodo consigliato:
1) Doppio click su:
   GreenBrain-Install.desktop

Oppure da terminale:
   chmod +x INSTALLA_GREENBRAIN_LINUX.run
   ./INSTALLA_GREENBRAIN_LINUX.run

REQUISITI
- Docker Desktop su Windows/Mac
- Docker Engine + Docker Compose su Linux
- Connessione internet durante la prima installazione

DATI CLIENTE
I dati cliente restano locali sul computer del cliente.
GreenBrain centrale gestisce login, routing, heartbeat e visualizzazione autorizzata.
TXT

python3 - <<PY
from pathlib import Path
import zipfile

out_dir = Path("$OUT_DIR")
zip_path = Path("$ZIP")

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for p in out_dir.iterdir():
        z.write(p, arcname=p.name)

print(f"Universal installer pronto: {zip_path}")
PY
