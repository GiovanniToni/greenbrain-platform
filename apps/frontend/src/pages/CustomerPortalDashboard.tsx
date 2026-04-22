import { useCallback, useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Download, CreditCard, CheckCircle2, AlertCircle,
  Package, Building2, Clock, Calendar,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  downloadCustomerPortalBundle,
  getCustomerPortalMe,
  bookSetupSlot,
  confirmDataOk,
} from "@/lib/customerPortalApi";
import { planDisplayName, planDisplayPrice } from "@/lib/planConfig";
import { createSetupSession } from "@/lib/customerBillingApi";

// ── helpers ──────────────────────────────────────────────────────────────────

function fmtDate(iso: string | undefined | null) {
  if (!iso) return null;
  try { return new Date(iso).toLocaleDateString("it-IT"); } catch { return iso; }
}

function fmtDateTime(iso: string | undefined | null) {
  if (!iso) return null;
  try { return new Date(iso).toLocaleString("it-IT"); } catch { return iso; }
}

function installBadge(status: string | undefined | null) {
  const s = (status || "").toLowerCase();
  if (s === "installed") return <Badge>Installato</Badge>;
  if (["pending", "in_progress"].includes(s)) return <Badge variant="secondary">{status}</Badge>;
  if (["failed", "error"].includes(s)) return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="outline">{status || "—"}</Badge>;
}

function slotTimeFmt(t: string | null | undefined) {
  if (t === "morning") return "Mattina";
  if (t === "afternoon") return "Pomeriggio";
  return t || "—";
}

function getLifecyclePhase(data: any): string {
  if (!data) return "loading";
  if ((data.subscription_status || "").toLowerCase() === "active") return "active";
  const s = (data.onboarding_status || "").toLowerCase();
  if (s === "data_validated") return "activating";
  if (s === "data_validation_pending") return "data_validation_pending";
  if (s === "setup_in_progress") return "setup_in_progress";
  if (s === "slot_confirmed") return "slot_confirmed";
  if (s === "slot_requested") return "slot_requested";
  if (data.payment_method_saved) return "payment_saved";
  return "no_payment";
}

// ── main component ────────────────────────────────────────────────────────────

export default function CustomerPortalDashboard() {
  const [searchParams] = useSearchParams();
  const setupStatus = searchParams.get("setup");
  const billingStatus = searchParams.get("billing");

  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [showRaw, setShowRaw] = useState(false);

  const [slotDate, setSlotDate] = useState("");
  const [slotTime, setSlotTime] = useState("morning");
  const [slotNotes, setSlotNotes] = useState("");
  const [bookingBusy, setBookingBusy] = useState(false);
  const [confirmDataBusy, setConfirmDataBusy] = useState(false);

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

  useEffect(() => {
    if (setupStatus !== "success" && billingStatus !== "success") return;
    const t = setTimeout(() => doFetch(true), 2500);
    return () => clearTimeout(t);
  }, [setupStatus, billingStatus, doFetch]);

  async function handleSavePaymentMethod() {
    try {
      setError(null);
      const plan = (data?.subscription_plan || "starter") as string;
      const res = await createSetupSession(plan);
      if (!res?.setup_url) throw new Error("setup_url mancante");
      window.location.href = res.setup_url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore avvio setup pagamento");
    }
  }

  async function handleBookSlot(e: React.FormEvent) {
    e.preventDefault();
    if (!slotDate) return;
    try {
      setBookingBusy(true);
      setError(null);
      await bookSetupSlot({
        preferred_date: slotDate,
        preferred_time: slotTime,
        notes: slotNotes.trim() || undefined,
      });
      doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore prenotazione slot");
    } finally {
      setBookingBusy(false);
    }
  }

  async function handleConfirmData() {
    try {
      setConfirmDataBusy(true);
      setError(null);
      await confirmDataOk();
      doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore conferma dati");
    } finally {
      setConfirmDataBusy(false);
    }
  }

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

  const phase = getLifecyclePhase(data);
  const bundleReady = Boolean(data?.delivery?.bundle_local_path);
  const planLabel = planDisplayName(data?.subscription_plan);
  const planPrice = planDisplayPrice(data?.subscription_plan);

  const bundleSubtitle = bundleReady
    ? "Pacchetto pronto — puoi scaricarlo ora"
    : data?.delivery?.bundle_generated_at
    ? "Bundle in preparazione finale"
    : data?.setup_slot_scheduled_for
    ? "Il bundle verrà preparato dopo la sessione di setup confermata"
    : data?.setup_slot_requested_at
    ? "Il bundle sarà disponibile dopo la conferma della sessione di setup"
    : "Il bundle verrà preparato dal team GreenBrain dopo la sessione di setup";

  const bundleButtonLabel = downloading
    ? "Download in corso..."
    : bundleReady
    ? "Scarica bundle GreenBrain"
    : data?.setup_slot_scheduled_for
    ? "Bundle in preparazione — non ancora disponibile"
    : "Bundle non ancora disponibile";

  const nextSteps = [
    {
      done: Boolean(data?.payment_method_saved),
      label: "Salva metodo di pagamento",
      detail: "Salva la tua carta per avviare il processo di attivazione.",
    },
    {
      done: Boolean(data?.setup_slot_requested_at),
      label: "Prenota la sessione di setup remoto",
      detail: "Scegli la tua disponibilità per la sessione di configurazione con il team.",
    },
    {
      done: Boolean(data?.setup_slot_scheduled_for),
      label: "Sessione di setup confermata",
      detail: "Il team GreenBrain confermerà la data e condurrà la sessione di configurazione.",
    },
    {
      done: Boolean(data?.data_validated_at),
      label: "Verifica e conferma i dati",
      detail: "Controlla i dati importati e confermali per sbloccare l'attivazione.",
    },
    {
      done: data?.subscription_status === "active",
      label: "Abbonamento attivato",
      detail: "L'abbonamento verrà attivato dal team dopo la conferma dei dati.",
    },
    {
      done: Boolean(data?.delivery?.bundle_generated_at),
      label: "Bundle GreenBrain pronto",
      detail: "Il pacchetto di installazione verrà preparato dal team.",
    },
    {
      done: data?.delivery?.install_status === "installed",
      label: "Installa GreenBrain",
      detail: "Segui la guida inclusa nel bundle per completare l'installazione.",
    },
  ];

  return (
    <div className="container mx-auto px-4 py-10 max-w-3xl space-y-5">

      {/* Banners */}
      {setupStatus === "success" && (
        <div className="flex items-start gap-3 bg-primary/5 border border-primary/20 rounded-xl px-4 py-3 text-sm">
          <CheckCircle2 className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
          <div>
            <strong>Metodo di pagamento salvato.</strong> Prenota ora la sessione di setup per continuare.
          </div>
        </div>
      )}
      {setupStatus === "cancel" && (
        <div className="flex items-start gap-3 bg-muted border border-border rounded-xl px-4 py-3 text-sm">
          <AlertCircle className="w-5 h-5 text-muted-foreground flex-shrink-0 mt-0.5" />
          <div>
            <strong>Pagamento annullato.</strong> Nessun dato è stato salvato. Puoi riprovare quando vuoi.
          </div>
        </div>
      )}
      {billingStatus === "success" && (
        <div className="flex items-start gap-3 bg-primary/5 border border-primary/20 rounded-xl px-4 py-3 text-sm">
          <CheckCircle2 className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
          <div>
            <strong>Pagamento completato.</strong> Il tuo abbonamento è ora attivo.
          </div>
        </div>
      )}
      {billingStatus === "cancel" && (
        <div className="flex items-start gap-3 bg-muted border border-border rounded-xl px-4 py-3 text-sm">
          <AlertCircle className="w-5 h-5 text-muted-foreground flex-shrink-0 mt-0.5" />
          <div>
            <strong>Pagamento annullato.</strong> Nessun addebito è stato effettuato.
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
            <span className="text-muted-foreground">Piano</span>
            <div className="text-right">
              <span>{planLabel}</span>
              {planPrice && <span className="text-xs text-muted-foreground ml-1.5">{planPrice}</span>}
            </div>
          </div>
          {data?.assigned_release_version && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Versione assegnata</span>
              <span>{data.assigned_release_version}</span>
            </div>
          )}
          {data?.installed_release_version && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Versione installata</span>
              <span>{data.installed_release_version}</span>
            </div>
          )}
        </div>
      </Card>

      {/* Lifecycle / activation card */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <CreditCard className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Attivazione &amp; Onboarding</h2>
              <p className="text-xs text-muted-foreground">
                {data?.onboarding_step ? `Step: ${data.onboarding_step}` : "Processo di attivazione guidato"}
              </p>
            </div>
          </div>
          {phase === "active" && <Badge>Attivo</Badge>}
          {phase === "activating" && <Badge variant="secondary">Attivazione in corso</Badge>}
          {phase === "data_validation_pending" && <Badge variant="secondary">Verifica dati</Badge>}
          {phase === "setup_in_progress" && <Badge variant="secondary">In corso</Badge>}
          {phase === "slot_confirmed" && <Badge variant="secondary">Confermato</Badge>}
          {phase === "slot_requested" && <Badge variant="outline">In attesa</Badge>}
          {phase === "payment_saved" && <Badge variant="outline">Pagamento salvato</Badge>}
          {phase === "no_payment" && <Badge variant="outline">In attesa</Badge>}
        </div>

        {/* Phase A: no payment method */}
        {phase === "no_payment" && (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Per avviare il processo di onboarding, salva il tuo metodo di pagamento. L&apos;abbonamento sarà attivato solo dopo la sessione di setup e la verifica dei dati.
            </p>
            <Button className="w-full" onClick={handleSavePaymentMethod}>
              <CreditCard className="w-4 h-4 mr-2" />
              Salva metodo di pagamento
            </Button>
          </div>
        )}

        {/* Phase B: payment saved, book slot */}
        {phase === "payment_saved" && (
          <div className="space-y-4">
            {data?.payment_method_last4 && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <CreditCard className="w-4 h-4" />
                <span>
                  {data.payment_method_brand ? `${data.payment_method_brand.toUpperCase()} ` : ""}
                  ••••&nbsp;{data.payment_method_last4}
                </span>
                <Badge variant="outline" className="text-xs ml-1">Salvata</Badge>
              </div>
            )}
            <p className="text-sm text-muted-foreground">
              Scegli la tua disponibilità per la sessione di configurazione remota con il team GreenBrain.
            </p>
            <form onSubmit={handleBookSlot} className="space-y-3 pt-1">
              <div className="grid sm:grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="slotDate" className="text-xs">Data preferita</Label>
                  <Input
                    id="slotDate"
                    type="date"
                    value={slotDate}
                    onChange={(e) => setSlotDate(e.target.value)}
                    required
                    min={new Date(Date.now() + 86400000).toISOString().slice(0, 10)}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="slotTime" className="text-xs">Orario preferito</Label>
                  <select
                    id="slotTime"
                    value={slotTime}
                    onChange={(e) => setSlotTime(e.target.value)}
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
                  >
                    <option value="morning">Mattina (9:00–13:00)</option>
                    <option value="afternoon">Pomeriggio (14:00–18:00)</option>
                  </select>
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="slotNotes" className="text-xs">Note (opzionale)</Label>
                <Input
                  id="slotNotes"
                  placeholder="Es. preferenza contatto, dettagli tecnici..."
                  value={slotNotes}
                  onChange={(e) => setSlotNotes(e.target.value)}
                />
              </div>
              <Button type="submit" className="w-full" disabled={bookingBusy || !slotDate}>
                <Calendar className="w-4 h-4 mr-2" />
                {bookingBusy ? "Prenotazione in corso..." : "Prenota sessione"}
              </Button>
            </form>
          </div>
        )}

        {/* Phase C: slot requested */}
        {phase === "slot_requested" && (
          <div className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              La tua richiesta è stata ricevuta. Il team GreenBrain ti contatterà per confermare la data.
            </p>
            <div className="flex flex-wrap gap-4 text-muted-foreground">
              {data?.setup_slot_preferred_date && (
                <span className="flex items-center gap-1.5">
                  <Calendar className="w-3.5 h-3.5" />
                  Data preferita: {fmtDate(data.setup_slot_preferred_date)}
                </span>
              )}
              {data?.setup_slot_preferred_time && (
                <span className="flex items-center gap-1.5">
                  <Clock className="w-3.5 h-3.5" />
                  {slotTimeFmt(data.setup_slot_preferred_time)}
                </span>
              )}
            </div>
          </div>
        )}

        {/* Phase C: slot confirmed */}
        {phase === "slot_confirmed" && (
          <div className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              La sessione di setup è confermata. Il team GreenBrain si connetterà con te alla data indicata.
            </p>
            {data?.setup_slot_scheduled_for && (
              <div className="flex items-center gap-2 text-muted-foreground">
                <Calendar className="w-4 h-4" />
                <span className="font-medium">{fmtDateTime(data.setup_slot_scheduled_for)}</span>
              </div>
            )}
          </div>
        )}

        {/* Phase C: setup in progress */}
        {phase === "setup_in_progress" && (
          <p className="text-sm text-muted-foreground">
            La sessione di configurazione è in corso con il team GreenBrain. Questo processo richiede solitamente 1–2 ore.
          </p>
        )}

        {/* Phase D: data validation pending */}
        {phase === "data_validation_pending" && (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              La configurazione è completata. Accedi a GreenBrain e verifica che i dati importati siano corretti. Quando sei pronto, conferma qui.
            </p>
            <Button className="w-full" onClick={handleConfirmData} disabled={confirmDataBusy}>
              <CheckCircle2 className="w-4 h-4 mr-2" />
              {confirmDataBusy ? "Conferma in corso..." : "Conferma dati corretti"}
            </Button>
          </div>
        )}

        {/* Phase E: activating */}
        {phase === "activating" && (
          <p className="text-sm text-muted-foreground">
            I dati sono stati confermati. L&apos;abbonamento è in fase di attivazione — riceverai conferma a breve.
          </p>
        )}

        {/* Phase E: active */}
        {phase === "active" && (
          <div className="flex items-center gap-2 text-sm">
            <CheckCircle2 className="w-4 h-4 text-primary" />
            <span>
              Abbonamento attivo{planLabel && planLabel !== "—" ? ` — ${planLabel}` : ""}
            </span>
          </div>
        )}
      </Card>

      {/* Gestione abbonamento */}
      <Card className="p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
            <CreditCard className="w-5 h-5 text-primary" />
          </div>
          <h2 className="font-semibold">Gestione abbonamento</h2>
        </div>
        <Separator className="my-4" />
        <div className="grid sm:grid-cols-2 gap-y-3 gap-x-6 text-sm mb-5">
          <div className="flex justify-between items-center">
            <span className="text-muted-foreground">Piano</span>
            <div className="text-right">
              <span>{planLabel}</span>
              {planPrice && <span className="text-xs text-muted-foreground ml-1.5">{planPrice}</span>}
            </div>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-muted-foreground">Stato abbonamento</span>
            <Badge variant={data?.subscription_status === "active" ? "default" : "outline"}>
              {data?.subscription_status || "—"}
            </Badge>
          </div>
          {data?.payment_method_saved && data?.payment_method_last4 && (
            <div className="flex justify-between items-center col-span-full">
              <span className="text-muted-foreground">Metodo di pagamento</span>
              <span className="flex items-center gap-1.5 text-xs">
                <CreditCard className="w-3.5 h-3.5" />
                {data.payment_method_brand ? `${data.payment_method_brand.toUpperCase()} ` : ""}
                ••••&nbsp;{data.payment_method_last4}
              </span>
            </div>
          )}
        </div>
        <Separator className="my-4" />
        {data?.cancellation_requested ? (
          <div className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 text-center">
            <p className="font-semibold">Disdetta richiesta il {fmtDate(data.cancellation_requested_at)}</p>
            <p className="text-xs text-amber-700 mt-1">In attesa gestione amministrativa</p>
          </div>
        ) : (
          <Button variant="outline" disabled className="w-full text-muted-foreground cursor-not-allowed">
            Richiedi disdetta
          </Button>
        )}
        <p className="text-xs text-muted-foreground mt-3 text-center">
          La gestione della disdetta viene effettuata tramite il team GreenBrain.
        </p>
      </Card>

      {/* Bundle & install */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <Package className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Bundle &amp; installazione</h2>
              <p className="text-xs text-muted-foreground">{bundleSubtitle}</p>
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
        {!bundleReady && !data?.setup_slot_requested_at && (
          <p className="text-xs text-muted-foreground mb-3">
            Per ricevere il bundle, completa prima la sessione di setup con il team GreenBrain.
          </p>
        )}
        <Button
          className="w-full"
          variant={bundleReady ? "default" : "outline"}
          onClick={handleDownloadBundle}
          disabled={!bundleReady || downloading}
        >
          <Download className="w-4 h-4 mr-2" />
          {bundleButtonLabel}
        </Button>
      </Card>

      {/* Next steps */}
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

      {/* Raw data debug */}
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
