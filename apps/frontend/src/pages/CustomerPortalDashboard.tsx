import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Download, CreditCard, CheckCircle2, AlertCircle,
  Package, Building2, Clock, User, RefreshCw,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import {
  downloadCustomerPortalBundle,
  getCustomerPortalMe,
} from "@/lib/customerPortalApi";
import { createPortalCheckout } from "@/lib/customerBillingApi";

// --- badge helpers per entità ---

function subscriptionBadge(status: string | undefined | null) {
  const s = (status || "").toLowerCase();
  if (s === "active") return <Badge>Attivo</Badge>;
  if (s === "checkout_started") return <Badge variant="secondary">In attesa</Badge>;
  if (s === "past_due") return <Badge variant="destructive">Scaduto</Badge>;
  if (s === "incomplete") return <Badge variant="destructive">Incompleto</Badge>;
  if (s === "canceled") return <Badge variant="outline">Annullato</Badge>;
  return <Badge variant="outline">Non attivo</Badge>;
}

function onboardingBadge(status: string | undefined | null) {
  const s = (status || "").toLowerCase();
  if (["completed", "active"].includes(s)) return <Badge>Completato</Badge>;
  if (["pending", "in_progress", "provisioning"].includes(s)) return <Badge variant="secondary">{status}</Badge>;
  if (["failed", "error"].includes(s)) return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="outline">{status || "—"}</Badge>;
}

function installBadge(status: string | undefined | null) {
  const s = (status || "").toLowerCase();
  if (s === "installed") return <Badge>Installato</Badge>;
  if (["pending", "in_progress"].includes(s)) return <Badge variant="secondary">{status}</Badge>;
  if (["failed", "error"].includes(s)) return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="outline">{status || "—"}</Badge>;
}

function fmtDate(iso: string | undefined | null) {
  if (!iso) return null;
  try { return new Date(iso).toLocaleDateString("it-IT"); } catch { return iso; }
}

function bundleSubtitle(subStatus: string | undefined | null, bundleReady: boolean) {
  if (bundleReady) return "Pacchetto disponibile per il download";
  const s = (subStatus || "").toLowerCase();
  if (s === "active") return "Provisioning in corso — il bundle sarà disponibile a breve";
  if (s === "checkout_started") return "Il bundle sarà disponibile appena l'abbonamento sarà confermato";
  return "Attiva l'abbonamento per sbloccare il download del bundle";
}

// --- componente principale ---

export default function CustomerPortalDashboard() {
  const [searchParams] = useSearchParams();
  const billingStatus = searchParams.get("billing");

  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [showRaw, setShowRaw] = useState(false);

  const doFetch = useCallback((silent = false) => {
    if (silent) setRefreshing(true);
    else setLoading(true);
    setError(null);
    getCustomerPortalMe()
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Errore caricamento"))
      .finally(() => { setLoading(false); setRefreshing(false); });
  }, []);

  useEffect(() => { doFetch(); }, [doFetch]);

  // Refresh silenzioso 2.5s dopo ritorno da Stripe (webhook può essere asincrono)
  useEffect(() => {
    if (billingStatus !== "success") return;
    const t = setTimeout(() => doFetch(true), 2500);
    return () => clearTimeout(t);
  }, [billingStatus, doFetch]);

  async function handleDownloadBundle() {
    try {
      setDownloading(true);
      setError(null);
      const { blob, filename } = await downloadCustomerPortalBundle();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore download bundle");
    } finally {
      setDownloading(false);
    }
  }

  async function handleStartCheckout() {
    try {
      setError(null);
      const res = await createPortalCheckout();
      if (!res?.checkout_url) throw new Error("checkout_url mancante");
      window.location.href = res.checkout_url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore avvio checkout");
    }
  }

  if (loading) {
    return (
      <div className="min-h-[60vh] flex items-center justify-center">
        <div className="text-center">
          <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-muted-foreground text-sm">Caricamento area cliente...</p>
        </div>
      </div>
    );
  }

  if (error && !data) {
    return (
      <div className="min-h-[60vh] flex items-center justify-center p-4">
        <Card className="p-8 max-w-sm w-full text-center">
          <AlertCircle className="w-10 h-10 text-destructive mx-auto mb-4" />
          <h2 className="font-semibold mb-2">Impossibile caricare i dati</h2>
          <p className="text-sm text-muted-foreground">{error}</p>
        </Card>
      </div>
    );
  }

  const subscriptionActive = data?.subscription_status === "active";
  const bundleReady = Boolean(data?.delivery?.bundle_local_path);

  const nextSteps = [
    {
      done: subscriptionActive,
      label: "Attiva abbonamento",
      detail: "Completa il pagamento dal portale per avviare il provisioning.",
    },
    {
      done: Boolean(data?.delivery?.bundle_generated_at),
      label: "Bundle in preparazione",
      detail: "Il tuo ambiente GreenBrain viene predisposto dal team.",
    },
    {
      done: bundleReady,
      label: "Scarica il pacchetto",
      detail: "Appena pronto, scaricalo dalla sezione Bundle.",
    },
    {
      done: data?.delivery?.install_status === "installed",
      label: "Installa GreenBrain",
      detail: "Segui la guida inclusa nel bundle per l'installazione.",
    },
    {
      done: Boolean(data?.delivery?.go_live_at),
      label: "Collega il gestionale",
      detail: "Integra GreenBrain con il tuo sistema gestionale con il supporto del team.",
    },
  ];

  return (
    <div className="container mx-auto px-4 py-10 max-w-3xl space-y-5">

      {/* Billing feedback */}
      {billingStatus === "success" && (
        <div className="flex items-start gap-3 bg-primary/5 border border-primary/20 rounded-xl px-4 py-3 text-sm">
          <CheckCircle2 className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
          <div>
            <strong>Pagamento completato.</strong> Il tuo abbonamento è ora attivo. Il provisioning del bundle partirà a breve.
          </div>
        </div>
      )}
      {billingStatus === "cancel" && (
        <div className="flex items-start gap-3 bg-muted border border-border rounded-xl px-4 py-3 text-sm">
          <AlertCircle className="w-5 h-5 text-muted-foreground flex-shrink-0 mt-0.5" />
          <div>
            <strong>Pagamento annullato.</strong> Nessun addebito è stato effettuato. Puoi riprovare quando vuoi.
          </div>
        </div>
      )}

      {/* Account overview */}
      <Card className="p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
            <Building2 className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="font-bold text-lg leading-tight">{data?.company_name || "—"}</h1>
            <p className="text-sm text-muted-foreground">{data?.portal_user_email || "—"}</p>
          </div>
        </div>
        <Separator className="my-4" />
        <div className="grid sm:grid-cols-2 gap-y-3 gap-x-6 text-sm">
          <div className="flex justify-between items-center">
            <span className="text-muted-foreground">Tenant</span>
            <span className="font-mono text-xs bg-muted px-2 py-0.5 rounded">{data?.tenant_code || "—"}</span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-muted-foreground">Versione assegnata</span>
            <span>{data?.assigned_release_version || "—"}</span>
          </div>
          {data?.installed_release_version && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Versione installata</span>
              <span>{data.installed_release_version}</span>
            </div>
          )}
        </div>
      </Card>

      {/* Subscription */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <CreditCard className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Abbonamento</h2>
              <p className="text-xs text-muted-foreground">Gestisci il tuo piano GreenBrain</p>
            </div>
          </div>
          {subscriptionBadge(data?.subscription_status || "non attivo")}
        </div>
        {!subscriptionActive && (
          <Button className="w-full" onClick={handleStartCheckout}>
            <CreditCard className="w-4 h-4 mr-2" />
            Attiva abbonamento
          </Button>
        )}
      </Card>

      {/* Onboarding */}
      <Card className="p-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <User className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Onboarding</h2>
              {data?.onboarding_step && (
                <p className="text-xs text-muted-foreground">Step corrente: {data.onboarding_step}</p>
              )}
            </div>
          </div>
          {onboardingBadge(data?.onboarding_status)}
        </div>
      </Card>

      {/* Bundle */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <Package className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Bundle & installazione</h2>
              <p className="text-xs text-muted-foreground">
                {bundleReady ? "Pacchetto disponibile per il download" : "In attesa di provisioning"}
              </p>
            </div>
          </div>
          {installBadge(data?.delivery?.install_status)}
        </div>
        {(data?.delivery?.bundle_generated_at || data?.delivery?.go_live_at) && (
          <div className="flex flex-wrap gap-4 text-xs text-muted-foreground mb-4">
            {data.delivery.bundle_generated_at && (
              <span className="flex items-center gap-1.5">
                <Clock className="w-3.5 h-3.5" />
                Generato: {fmtDate(data.delivery.bundle_generated_at)}
              </span>
            )}
            {data.delivery.go_live_at && (
              <span className="flex items-center gap-1.5">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Go-live: {fmtDate(data.delivery.go_live_at)}
              </span>
            )}
          </div>
        )}
        <Button
          className="w-full"
          variant={bundleReady ? "default" : "outline"}
          onClick={handleDownloadBundle}
          disabled={!bundleReady || downloading}
        >
          <Download className="w-4 h-4 mr-2" />
          {downloading ? "Download in corso..." : bundleReady ? "Scarica bundle" : "Bundle non ancora disponibile"}
        </Button>
      </Card>

      {/* Prossimi passi */}
      <Card className="p-6">
        <h2 className="font-semibold mb-5">Prossimi passi</h2>
        <ol className="space-y-4">
          {nextSteps.map(({ done, label, detail }, i) => (
            <li key={i} className="flex items-start gap-3">
              <div className={`w-5 h-5 rounded-full flex-shrink-0 mt-0.5 border-2 ${done ? "bg-primary border-primary" : "border-border"}`} />
              <div>
                <p className={`text-sm font-medium leading-snug ${done ? "line-through text-muted-foreground" : ""}`}>
                  {label}
                </p>
                {!done && <p className="text-xs text-muted-foreground mt-0.5">{detail}</p>}
              </div>
            </li>
          ))}
        </ol>
      </Card>

      {/* Error */}
      {error && (
        <div className="flex items-center gap-3 bg-destructive/10 border border-destructive/30 rounded-xl px-4 py-3 text-sm text-destructive">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          {error}
        </div>
      )}

      {/* Raw data */}
      <div className="pt-1 pb-6">
        <button
          className="text-xs text-muted-foreground hover:text-foreground underline"
          onClick={() => setShowRaw((v) => !v)}
        >
          {showRaw ? "Nascondi" : "Mostra"} dati tecnici
        </button>
        {showRaw && (
          <pre className="mt-3 text-xs bg-muted rounded-xl p-4 overflow-auto max-h-64 text-muted-foreground">
            {JSON.stringify(data, null, 2)}
          </pre>
        )}
      </div>
    </div>
  );
}
