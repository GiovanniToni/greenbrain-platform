import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

type SyncStatus = "idle" | "running" | "synced" | "no_pending" | "error" | "not_local";

type SyncResult = {
  status?: string;
  tenant_code?: string;
  installation_id?: string;
  email?: string;
  password_version?: number;
  password_last_sync_status?: string;
  ack_http_status?: number;
  ack_status?: string;
  detail?: string;
};

function isLocalHost(hostname: string): boolean {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
}

export default function LocalPasswordSync() {
  const [status, setStatus] = useState<SyncStatus>("idle");
  const [message, setMessage] = useState("Preparazione sincronizzazione password locale...");
  const [result, setResult] = useState<SyncResult | null>(null);

  const local = useMemo(() => isLocalHost(window.location.hostname), []);

  async function runSync() {
    if (!local) {
      setStatus("not_local");
      setMessage("Questa pagina deve essere aperta dal GreenBrain locale su localhost.");
      return;
    }

    try {
      setStatus("running");
      setMessage("Sincronizzazione password locale in corso...");
      setResult(null);

      const response = await fetch("/api/v1/customer-runtime/password-sync/run-local", {
        method: "POST",
        headers: { Accept: "application/json" },
      });

      const body = await response.json().catch(() => null);
      setResult(body);

      if (!response.ok) {
        setStatus("error");
        setMessage(body?.detail || `Sincronizzazione non riuscita. HTTP ${response.status}`);
        return;
      }

      if (body?.status === "synced") {
        setStatus("synced");
        setMessage("Password locale sincronizzata correttamente.");
        return;
      }

      if (body?.status === "no_pending") {
        setStatus("no_pending");
        setMessage("GreenBrain locale risulta già allineato.");
        return;
      }

      setStatus("error");
      setMessage("Risposta non riconosciuta dal runtime locale.");
    } catch (err) {
      setStatus("error");
      setMessage(err instanceof Error ? err.message : "Errore durante la sincronizzazione locale.");
    }
  }

  useEffect(() => {
    void runSync();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isBusy = status === "running";

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <Card className="max-w-lg w-full p-6 space-y-5">
        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
            GreenBrain locale
          </p>
          <h1 className="text-2xl font-semibold">Sincronizzazione password</h1>
          <p className="text-sm text-muted-foreground mt-2">
            Questa pagina comunica con il runtime locale GreenBrain installato su questo computer.
          </p>
        </div>

        <div className="rounded-lg border bg-muted/30 p-4">
          <p className="font-medium">{message}</p>
          {isBusy && (
            <p className="text-sm text-muted-foreground mt-2">
              Attendere qualche secondo...
            </p>
          )}
        </div>

        {result && (
          <div className="rounded-lg border p-4 text-xs overflow-auto max-h-64">
            <p className="font-semibold mb-2">Dettagli tecnici</p>
            <pre>{JSON.stringify(result, null, 2)}</pre>
          </div>
        )}

        <div className="flex flex-col sm:flex-row gap-3">
          <Button type="button" onClick={runSync} disabled={isBusy}>
            {isBusy ? "Sincronizzazione..." : "Riprova sincronizzazione"}
          </Button>

          <Button
            type="button"
            variant="outline"
            onClick={() => {
              window.location.href = "/";
            }}
          >
            Apri GreenBrain locale
          </Button>
        </div>

        <p className="text-xs text-muted-foreground">
          Se questa pagina non riesce a sincronizzare, GreenBrain locale si allineerà comunque
          automaticamente al prossimo heartbeat.
        </p>
      </Card>
    </div>
  );
}
