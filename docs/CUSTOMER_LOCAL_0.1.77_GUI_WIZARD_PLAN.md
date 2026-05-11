# GreenBrain Customer Local 0.1.77 — GUI Wizard Plan

## Problema

Il file `GreenBrain-Install.desktop` può essere aperto da IDE/editor invece che eseguito come launcher.
Inoltre l'installazione attuale è ancora terminal-based, non una vera finestra wizard.

## Analisi ambiente

- `zenity`: non disponibile
- `yad`: non disponibile
- `tkinter`: non disponibile
- `gtk-launch`: non disponibile
- `python3`: disponibile
- Python stdlib `http.server`: disponibile
- Browser opener disponibile via `sensible-browser` / `gio`

## Decisione tecnica

Implementare un wizard HTML locale servito da Python stdlib:

- nuovo path: `base/apps/local-installer-wizard/`
- avvio da `INSTALL_GREENBRAIN.sh`
- apertura browser locale su `http://127.0.0.1:<porta-wizard>`
- UI con logo/favicon GreenBrain
- step guidati:
  1. Benvenuto
  2. Dati cliente
  3. Provisioning
  4. Opzione Source DB
  5. Installazione
  6. Verifica finale
- pulsanti:
  - Avanti
  - Indietro
  - Installa
  - Verifica stato
  - Apri GreenBrain
- fallback terminale se browser/wizard non parte

## Non goals

- Nessun cambio architetturale
- Nessun test SQL Server reale
- Nessuna dipendenza GUI esterna
- Non rompere `install.sh` esistente

## Strategia sicura

1. Aggiungere wizard come layer sopra l'installazione esistente.
2. Mantenere `install.sh` come fallback.
3. Validare prima apertura wizard.
4. Solo dopo collegare il pulsante `Installa` al processo reale.
