import { useCallback, useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
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
  cancelPortalSubscription,
  downloadCustomerPortalBundle,
  getCustomerPortalMe,
  bookSetupSlot,
  confirmDataOk,
} from "@/lib/customerPortalApi";
import { planDisplayName, planDisplayPrice } from "@/lib/planConfig";
import { createSetupSession } from "@/lib/customerBillingApi";
import { useAuth } from "@/hooks/useAuth";

type LifecyclePhase =
  | "loading"
  | "active"
  | "activating"
  | "data_validation_pending"
  | "setup_in_progress"
  | "slot_confirmed"
  | "slot_requested"
  | "payment_saved"
  | "no_payment";

interface CustomerDeliveryProfile {
  assigned_release_version?: string | null;
  bundle_generated_at?: string | null;
  bundle_sent_at?: string | null;
  bundle_local_path?: string | null;
  install_status?: string | null;
  onboarding_status?: string | null;
  go_live_at?: string | null;
  updated_at?: string | null;
}

interface CustomerPortalProfile {
  customer_id?: string | null;
  tenant_code?: string | null;
  company_name?: string | null;
  portal_user_email?: string | null;
  onboarding_status?: string | null;
  onboarding_step?: string | null;
  assigned_release_version?: string | null;
  installed_release_version?: string | null;
  runtime_connection_status?: string | null;
  latest_installation_id?: string | null;
  last_runtime_heartbeat_at?: string | null;
  runtime_public_backend_url?: string | null;
  runtime_local_backend_url?: string | null;
  runtime_local_agent_version?: string | null;
  runtime_connection_mode?: string | null;
  runtime_last_sync_status?: string | null;
  runtime_last_sync_at?: string | null;
  platform_ready?: boolean;
  installation_status?: string | null;
  installation_status_label?: string | null;
  installation_next_action?: string | null;
  first_downloaded_release_version?: string | null;
  first_downloaded_at?: string | null;
  last_downloaded_release_version?: string | null;
  last_downloaded_at?: string | null;
  latest_available_release_version?: string | null;
  subscription_status?: string | null;
  subscription_plan?: string | null;
  payment_method_saved?: boolean;
  payment_method_last4?: string | null;
  payment_method_brand?: string | null;
  setup_slot_preferred_date?: string | null;
  setup_slot_preferred_time?: string | null;
  setup_slot_requested_at?: string | null;
  setup_slot_confirmed_at?: string | null;
  setup_slot_scheduled_for?: string | null;
  data_validated_at?: string | null;
  cancellation_requested?: boolean;
  cancellation_requested_at?: string | null;
  subscription_current_period_end?: string | null;
  subscription_activated_at?: string | null;
  subscription_cancel_at_period_end?: boolean;
  created_at?: string | null;
  updated_at?: string | null;
  delivery?: CustomerDeliveryProfile | null;
}

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

function getLifecyclePhase(data: CustomerPortalProfile | null): LifecyclePhase {
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


function isLocalRuntimeHost() {
  if (typeof window === "undefined") return false;
  const host = window.location.hostname;
  return host === "localhost" || host === "127.0.0.1";
}

function LocalRuntimeAccount() {
  const { user } = useAuth();

  const dashboardPath = user?.home_path?.trim() || "/dashboard";
  const cloudAccountUrl = "https://www.greenbrain.it/account";

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
          <div>
            <h1 className="text-2xl font-bold">Il mio account locale</h1>
            <p className="text-sm text-muted-foreground mt-1">
              Questo profilo è usato da GreenBrain Customer Local su questo computer.
            </p>
          </div>
          {user?.platform_enabled && (
            <Button asChild>
              <Link to={dashboardPath}>Vai alla Dashboard</Link>
            </Button>
          )}
        </div>

        <Separator className="my-5" />

        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <p className="text-sm text-muted-foreground">Email locale</p>
            <p className="font-medium">{user?.email ?? "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Nome</p>
            <p className="font-medium">{user?.full_name ?? "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Tenant</p>
            <p className="font-medium">{user?.tenant_code ?? "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Ruolo</p>
            <p className="font-medium">{user?.user_role ?? "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Piattaforma locale</p>
            <p className="font-medium">
              {user?.platform_enabled ? "Attiva" : "Non attiva"}
            </p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Pagina iniziale</p>
            <p className="font-medium">{dashboardPath}</p>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <h2 className="text-xl font-semibold">Dettagli abbonamento</h2>
        <p className="text-sm text-muted-foreground mt-2">
          Abbonamento, pagamenti, download del bundle e gestione account rimangono
          nel portale cloud GreenBrain.
        </p>
        <div className="mt-4 flex flex-wrap gap-3">
          <Button variant="outline" asChild>
            <a href={cloudAccountUrl} target="_blank" rel="noreferrer">
              Apri account cloud GreenBrain
            </a>
          </Button>
          {user?.platform_enabled && (
            <Button asChild>
              <Link to={dashboardPath}>Torna alla piattaforma locale</Link>
            </Button>
          )}
        </div>
      </Card>
    </div>
  );
}


// ── main component ────────────────────────────────────────────────────────────

export default function CustomerPortalDashboard() {
  if (isLocalRuntimeHost()) {
    return <LocalRuntimeAccount />;
  }

  const [searchParams] = useSearchParams();
  const setupStatus = searchParams.get("setup");
  const billingStatus = searchParams.get("billing");

  const [data, setData] = useState<CustomerPortalProfile | null>(null);
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
  const [cancelBusy, setCancelBusy] = useState(false);
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);

  const doFetch = useCallback(async (silent = false) => {
    if (silent) setRefreshing(true);
    else setLoading(true);
    setError(null);

    try {
      const profile = await getCustomerPortalMe();
      setData(profile);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore caricamento");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
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
      await doFetch(true);
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
      await doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore conferma dati");
    } finally {
      setConfirmDataBusy(false);
    }
  }

  async function handleCancelSubscription() {
    try {
      setCancelBusy(true);
      setError(null);
      await cancelPortalSubscription();
      setShowCancelConfirm(false);
      await doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore disdetta");
      setShowCancelConfirm(false);
    } finally {
      setCancelBusy(false);
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

      setData((prev) => prev ? {
        ...prev,
        first_downloaded_release_version: prev.first_downloaded_release_version || prev.latest_available_release_version,
        first_downloaded_at: prev.first_downloaded_at || new Date().toISOString(),
        last_downloaded_release_version: prev.latest_available_release_version,
        last_downloaded_at: new Date().toISOString(),
      } : prev);
      await doFetch(true);
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
  const bundleAvailable = Boolean(
    data?.latest_available_release_version || data?.delivery?.bundle_generated_at || data?.delivery?.bundle_local_path
  );
  const bundleDownloadEnabled = Boolean(
    data?.payment_method_saved &&
    data?.setup_slot_requested_at &&
    (data?.setup_slot_confirmed_at || data?.setup_slot_scheduled_for) &&
    bundleAvailable
  );
  const planLabel = planDisplayName(data?.subscription_plan);
  const planPrice = planDisplayPrice(data?.subscription_plan);

  const latestAvailableVersion = data?.latest_available_release_version || null;
  const firstDownloadedVersion = data?.first_downloaded_release_version || null;
  const firstDownloadedAt = data?.first_downloaded_at || null;
  const lastDownloadedVersion = data?.last_downloaded_release_version || null;
  const lastDownloadedAt = data?.last_downloaded_at || null;
  const hasNeverDownloaded = !lastDownloadedAt;
  const subscriptionCancelAtPeriodEnd = Boolean(data?.subscription_cancel_at_period_end);
  const subscriptionCurrentPeriodEnd = data?.subscription_current_period_end || null;
  const subscriptionActivatedAt = data?.subscription_activated_at || null;
  const isSubscriptionActive = (data?.subscription_status || "").toLowerCase() === "active";

  const hasUpdateAvailable = Boolean(
    latestAvailableVersion &&
    lastDownloadedVersion &&
    latestAvailableVersion !== lastDownloadedVersion
  );

  const bundleButtonIsPrimary = Boolean(
    bundleDownloadEnabled && (hasNeverDownloaded || hasUpdateAvailable)
  );

  const bundleSubtitle = !data?.payment_method_saved
    ? "Il download si attiverà dopo il salvataggio del metodo di pagamento"
    : !data?.setup_slot_requested_at
    ? "Il download si attiverà dopo la richiesta della sessione di setup"
    : !(data?.setup_slot_confirmed_at || data?.setup_slot_scheduled_for)
    ? "Il download si attiverà dopo la conferma della sessione di setup"
    : !bundleAvailable
    ? "Il bundle sarà disponibile quando la release sarà pronta"
    : hasNeverDownloaded
    ? `Pronto per il primo download${latestAvailableVersion ? `: versione ${latestAvailableVersion}` : ""}`
    : hasUpdateAvailable
    ? `Aggiornamento disponibile: ${latestAvailableVersion}`
    : latestAvailableVersion
    ? `Versione già scaricata: ${latestAvailableVersion}`
    : "Ultima versione disponibile pronta per il download";

  const bundleButtonLabel = downloading
    ? "Download in corso..."
    : !bundleDownloadEnabled
    ? "Bundle non ancora disponibile"
    : hasNeverDownloaded && latestAvailableVersion
    ? `Scarica versione ${latestAvailableVersion}`
    : hasUpdateAvailable && latestAvailableVersion
    ? `Scarica nuova versione ${latestAvailableVersion}`
    : latestAvailableVersion
    ? `Scarica di nuovo versione ${latestAvailableVersion}`
    : "Scarica l'ultima versione disponibile";

  const nextSteps = [
    {
      done: Boolean(data?.payment_method_saved),
      label: "Salva metodo di pagamento",
      detail: "Salva la carta in modo sicuro. Nessun abbonamento viene attivato in questa fase.",
    },
    {
      done: Boolean(data?.setup_slot_requested_at),
      label: "Richiedi la sessione di setup",
      detail: "Indica la tua disponibilità per la configurazione remota con il team GreenBrain.",
    },
    {
      done: Boolean(data?.setup_slot_confirmed_at || data?.setup_slot_scheduled_for),
      label: "Slot di setup confermato",
      detail: "Il team GreenBrain confermerà data e orario della sessione.",
    },
    {
      done: Boolean(lastDownloadedAt),
      label: "Scarica il bundle GreenBrain",
      detail: "Il bundle si scarica dopo la conferma dello slot e serve per procedere al setup.",
    },
    {
      done: Boolean(
        data?.installed_release_version ||
        data?.delivery?.install_status === "installed" ||
        data?.data_validated_at ||
        isSubscriptionActive
      ),
      label: "Setup e installazione",
      detail: "Durante la sessione remota viene configurato l'ambiente cliente.",
    },
    {
      done: Boolean(data?.data_validated_at),
      label: "Verifica e conferma i dati",
      detail: "Controlla i dati importati e confermali per autorizzare l'attivazione.",
    },
    {
      done: isSubscriptionActive,
      label: "Abbonamento attivato",
      detail: "L'abbonamento viene attivato solo dopo setup e conferma dei dati.",
    },
  ];

  const compactSteps = [
    { key: "payment", label: "Metodo pagamento", done: Boolean(data?.payment_method_saved) },
    { key: "slot", label: "Slot confermato", done: Boolean(data?.setup_slot_confirmed_at || data?.setup_slot_scheduled_for) },
    { key: "download", label: "Download", done: Boolean(lastDownloadedAt) },
    {
      key: "setup",
      label: "Setup",
      done: Boolean(
        data?.installed_release_version ||
        data?.delivery?.install_status === "installed" ||
        data?.data_validated_at ||
        isSubscriptionActive
      ),
    },
    { key: "data", label: "Dati confermati", done: Boolean(data?.data_validated_at) },
    { key: "subscription", label: "Abbonamento", done: isSubscriptionActive },
  ];

  const completedStepCount = compactSteps.filter((step) => step.done).length;
  const firstIncompleteStepIndex = compactSteps.findIndex((step) => !step.done);
  const activeStepIndex = firstIncompleteStepIndex === -1 ? compactSteps.length - 1 : firstIncompleteStepIndex;

  const nextActionTitle =
    phase === "no_payment"
      ? "Salva il metodo di pagamento"
      : phase === "payment_saved"
      ? "Prenota la sessione di setup"
      : phase === "slot_requested"
      ? "Attendi la conferma dello slot"
      : phase === "slot_confirmed"
      ? bundleDownloadEnabled
        ? "Scarica il bundle GreenBrain"
        : "Bundle in preparazione"
      : phase === "setup_in_progress"
      ? "Completa il setup remoto"
      : phase === "data_validation_pending"
      ? "Conferma i dati importati"
      : phase === "active"
      ? hasUpdateAvailable
        ? "Scarica il nuovo aggiornamento"
        : "GreenBrain è attivo"
      : "Attendi l'attivazione";

  const nextActionDescription =
    phase === "no_payment"
      ? "La carta viene salvata in modo sicuro. L'abbonamento non viene ancora attivato."
      : phase === "payment_saved"
      ? "Indica data e fascia oraria preferite per la configurazione remota."
      : phase === "slot_requested"
      ? "Abbiamo ricevuto la tua richiesta. Il team GreenBrain ti contatterà per confermare la sessione."
      : phase === "slot_confirmed"
      ? bundleDownloadEnabled
        ? "Scarica il file da usare durante la sessione remota di setup."
        : "Il download sarà disponibile appena la release sarà pronta."
      : phase === "setup_in_progress"
      ? "Il team GreenBrain sta configurando l'ambiente cliente."
      : phase === "data_validation_pending"
      ? "Controlla i dati importati e confermali per autorizzare l'attivazione."
      : phase === "active"
      ? hasUpdateAvailable
        ? "È disponibile una nuova versione del bundle GreenBrain."
        : "Il servizio è attivo. Puoi usare GreenBrain e scaricare nuovamente il bundle se necessario."
      : "I dati sono stati confermati. L'abbonamento sarà attivato dal team.";

  return (
    <div className="container mx-auto px-4 py-8 max-w-5xl space-y-5">

      {/* Banners */}
      {setupStatus === "success" && data?.payment_method_saved && !data?.setup_slot_requested_at && (
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
            <strong>Operazione completata.</strong> Stiamo aggiornando lo stato del tuo account.
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

      {bundleDownloadEnabled && hasUpdateAvailable && latestAvailableVersion && (
        <div className="flex items-start gap-3 bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-sm text-amber-900">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div>
            <strong>Nuova versione disponibile.</strong>{" "}
            È disponibile la versione {latestAvailableVersion}. Scarica il nuovo bundle per aggiornare GreenBrain.
          </div>
        </div>
      )}

      {error && data && (
        <div className="flex items-center gap-3 bg-destructive/10 border border-destructive/30 rounded-xl px-4 py-3 text-sm text-destructive">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          {error}
        </div>
      )}

      {/* Hero / prossima azione */}
      <Card className="p-6 border-primary/20 bg-gradient-to-br from-primary/5 to-background">
        <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-5">
          <div className="space-y-2">
            {refreshing && (
              <div className="text-xs text-muted-foreground animate-pulse">Aggiornamento dati...</div>
            )}
            <div className="flex items-center gap-2 flex-wrap">
              <Badge variant={phase === "active" ? "default" : "secondary"}>
                {phase === "active"
                  ? "Servizio attivo"
                  : phase === "no_payment"
                  ? "Pagamento da salvare"
                  : phase === "payment_saved"
                  ? "Setup da prenotare"
                  : phase === "slot_requested"
                  ? "Slot richiesto"
                  : phase === "slot_confirmed"
                  ? "Setup confermato"
                  : phase === "setup_in_progress"
                  ? "Setup in corso"
                  : phase === "data_validation_pending"
                  ? "Dati da confermare"
                  : "Attivazione in corso"}
              </Badge>
              {hasUpdateAvailable && (
                <Badge variant="secondary" className="bg-amber-50 text-amber-800 border border-amber-200">
                  Aggiornamento disponibile
                </Badge>
              )}
              {data?.cancellation_requested && (
                <Badge variant="secondary" className="bg-amber-50 text-amber-800 border border-amber-200">
                  Rinnovo disattivato
                </Badge>
              )}
            </div>

            <div>
              <h1 className="text-2xl font-bold leading-tight">
                Area cliente GreenBrain
              </h1>
              <p className="text-sm text-muted-foreground mt-1">
                {data?.company_name || "La tua azienda"}
                {planLabel && planLabel !== "—" ? ` · ${planLabel}` : ""}
                {planPrice ? ` ${planPrice}` : ""}
                {data?.subscription_status ? ` · Abbonamento ${data.subscription_status}` : ""}
              </p>
            </div>

            <p className="text-sm text-muted-foreground max-w-2xl">
              Gestisci onboarding, bundle, setup remoto e abbonamento da un’unica area riservata.
            </p>
          </div>

          <div className="flex flex-col gap-3 min-w-full sm:min-w-[260px] lg:min-w-[320px] rounded-2xl border border-primary/15 bg-background/80 p-4 shadow-sm">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Prossima azione
            </p>

            <div>
              <h2 className="text-base font-semibold leading-tight">{nextActionTitle}</h2>
              <p className="text-xs text-muted-foreground mt-1">{nextActionDescription}</p>
            </div>

            {phase === "no_payment" && (
              <Button onClick={handleSavePaymentMethod}>
                <CreditCard className="w-4 h-4 mr-2" />
                Salva metodo di pagamento
              </Button>
            )}

            {phase === "payment_saved" && (
              <Button
                variant="outline"
                onClick={() => document.getElementById("slotDate")?.focus()}
              >
                <Calendar className="w-4 h-4 mr-2" />
                Vai alla prenotazione
              </Button>
            )}

            {phase === "data_validation_pending" && (
              <Button onClick={handleConfirmData} disabled={confirmDataBusy}>
                <CheckCircle2 className="w-4 h-4 mr-2" />
                {confirmDataBusy ? "Conferma in corso..." : "Conferma dati corretti"}
              </Button>
            )}

            {bundleDownloadEnabled && (phase === "slot_confirmed" || phase === "active") && (
              <Button
                variant={bundleButtonIsPrimary ? "default" : "outline"}
                onClick={handleDownloadBundle}
                disabled={downloading}
              >
                <Download className="w-4 h-4 mr-2" />
                {bundleButtonLabel}
              </Button>
            )}
          </div>
        </div>
      </Card>

      {/* Progress attivazione */}
      <Card className="p-5">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
          <div>
            <h2 className="font-semibold text-sm">Avanzamento attivazione</h2>
            <p className="text-xs text-muted-foreground">
              {completedStepCount} di {compactSteps.length} passaggi completati
            </p>
          </div>
          <Badge variant={phase === "active" ? "default" : "secondary"}>
            {phase === "active" ? "Completato" : "In corso"}
          </Badge>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          {compactSteps.map((step, i) => {
            const isCurrent = i === activeStepIndex && !step.done;
            return (
              <div
                key={step.key}
                className={`rounded-xl border px-3 py-3 text-center ${
                  step.done
                    ? "bg-primary/5 border-primary/20"
                    : isCurrent
                    ? "bg-background border-primary/40 shadow-sm"
                    : "bg-muted/30 border-border"
                }`}
              >
                <div className={`w-7 h-7 rounded-full mx-auto mb-2 flex items-center justify-center text-xs font-bold ${
                  step.done
                    ? "bg-primary text-primary-foreground"
                    : isCurrent
                    ? "border border-primary text-primary"
                    : "border border-border text-muted-foreground"
                }`}>
                  {step.done ? "✓" : i + 1}
                </div>
                <p className={`text-xs font-medium ${
                  step.done ? "text-foreground" : isCurrent ? "text-primary" : "text-muted-foreground"
                }`}>
                  {step.label}
                </p>
              </div>
            );
          })}
        </div>
      </Card>

      {/* Lifecycle / activation card */}
      <Card className="p-6 border-primary/20 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
              <CreditCard className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold">Percorso guidato di attivazione</h2>
              <p className="text-xs text-muted-foreground">
                {data?.onboarding_step ? `Step: ${data.onboarding_step}` : "Completa i passaggi richiesti per iniziare a usare GreenBrain"}
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
              La tua richiesta è stata ricevuta. Il team GreenBrain ti contatterà per confermare la data e preparare la sessione di configurazione.
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


      <div className="grid lg:grid-cols-2 gap-5">
      {/* Account overview */}
      <Card className="p-6">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center">
            <Building2 className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h2 className="font-bold text-lg leading-tight">{data?.company_name || "—"}</h2>
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
        <div className="mt-3 text-xs text-muted-foreground text-center space-y-1">
          {subscriptionActivatedAt && (
            <p>Abbonamento attivato il: {fmtDateTime(subscriptionActivatedAt)}</p>
          )}
          {subscriptionCurrentPeriodEnd && subscriptionCancelAtPeriodEnd && (
            <p>Servizio disponibile fino al: {fmtDateTime(subscriptionCurrentPeriodEnd)}</p>
          )}
          {subscriptionCurrentPeriodEnd && !subscriptionCancelAtPeriodEnd && (
            <p>Prossimo addebito: {fmtDateTime(subscriptionCurrentPeriodEnd)}</p>
          )}
          {subscriptionCancelAtPeriodEnd && (
            <p>Rinnovo automatico disattivato</p>
          )}
        </div>
      </Card>

      </div>


      {/* Runtime status */}
      <Card className="p-6 border-primary/10">
        <h2 className="font-semibold mb-4">Runtime locale</h2>
        <div className="grid sm:grid-cols-3 gap-3">
          <div className="rounded-xl border bg-muted/20 p-4">
            <p className="text-xs text-muted-foreground mb-1">Stato connessione</p>
            <Badge variant={data?.runtime_connection_status === "healthy" ? "default" : "outline"}>
              {data?.runtime_connection_status || "Non collegato"}
            </Badge>
          </div>
          <div className="rounded-xl border bg-muted/20 p-4">
            <p className="text-xs text-muted-foreground mb-1">Ultimo heartbeat</p>
            <p className="font-semibold text-sm">
              {data?.last_runtime_heartbeat_at ? fmtDateTime(data.last_runtime_heartbeat_at) : "Mai ricevuto"}
            </p>
          </div>
          <div className="rounded-xl border bg-muted/20 p-4">
            <p className="text-xs text-muted-foreground mb-1">Installazione</p>
            <p className="font-mono text-xs break-all">
              {data?.latest_installation_id || "Non registrata"}
            </p>
          </div>
        </div>
      </Card>

      {/* Bundle & install */}
      <Card className="p-6 border-primary/10">
        <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-5 mb-5">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0">
              <Package className="w-5 h-5 text-primary" />
            </div>
            <div>
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="font-semibold">Bundle &amp; installazione</h2>
                {hasUpdateAvailable && (
                  <Badge variant="secondary" className="bg-amber-50 text-amber-800 border border-amber-200">
                    Nuova versione
                  </Badge>
                )}
              </div>
              <p className="text-xs text-muted-foreground mt-1">{bundleSubtitle}</p>
            </div>
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-3 mb-5">
          <div className="rounded-xl border bg-muted/20 p-4">
            <p className="text-xs text-muted-foreground mb-1">Versione disponibile</p>
            <p className="font-semibold text-sm">{latestAvailableVersion || "In preparazione"}</p>
            <p className="text-xs text-muted-foreground mt-1">
              Release GreenBrain pronta per il setup o per l’aggiornamento.
            </p>
          </div>

          <div className="rounded-xl border bg-muted/20 p-4">
            <p className="text-xs text-muted-foreground mb-1">Ultimo download</p>
            <p className="font-semibold text-sm">{lastDownloadedVersion || "Non ancora scaricato"}</p>
            {lastDownloadedAt ? (
              <p className="text-xs text-muted-foreground mt-1">{fmtDateTime(lastDownloadedAt)}</p>
            ) : (
              <p className="text-xs text-muted-foreground mt-1">
                Verrà registrato automaticamente dopo il primo download.
              </p>
            )}
          </div>
        </div>

        {firstDownloadedAt && (
          <div className="rounded-xl border border-primary/10 bg-primary/5 px-4 py-3 text-xs text-muted-foreground mb-4">
            Primo download effettuato il {fmtDateTime(firstDownloadedAt)}
            {firstDownloadedVersion ? ` · versione ${firstDownloadedVersion}` : ""}
          </div>
        )}

        {!bundleDownloadEnabled && (
          <div className="rounded-xl border bg-muted/30 px-4 py-3 text-xs text-muted-foreground mb-4">
            Il download verrà sbloccato automaticamente quando metodo di pagamento, slot di setup e disponibilità del bundle saranno confermati.
          </div>
        )}

        <Button
          className={bundleButtonIsPrimary ? "w-full bg-primary text-primary-foreground hover:bg-primary/90" : "w-full"}
          variant={bundleButtonIsPrimary ? "default" : "outline"}
          onClick={handleDownloadBundle}
          disabled={!bundleDownloadEnabled || downloading}
        >
          <Download className="w-4 h-4 mr-2" />
          {bundleButtonLabel}
        </Button>

        {bundleDownloadEnabled && (
          <p className="text-xs text-muted-foreground text-center mt-3">
            Usa questo file durante la sessione remota di setup o per aggiornare GreenBrain.
          </p>
        )}
      </Card>

      {nextSteps.some((step) => !step.done) && (
      <Card className="p-6">
        <h2 className="font-semibold mb-1">Checklist di attivazione</h2>
        <p className="text-xs text-muted-foreground mb-5">
          Segui questi passaggi per completare l’avvio di GreenBrain.
        </p>
        <ol className="space-y-4">
          {nextSteps.map(({ done, label, detail }, i) => (
            <li key={i} className="flex items-start gap-3">
              <div className={`w-6 h-6 rounded-full flex-shrink-0 mt-0.5 border-2 flex items-center justify-center text-[10px] font-bold ${done ? "bg-primary border-primary text-primary-foreground" : "border-border text-muted-foreground"}`}>
                {done ? "✓" : i + 1}
              </div>
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
      )}

      {(isSubscriptionActive || data?.cancellation_requested) && (
      <Card className="p-6">
        <div className="flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h2 className="font-semibold">Disdetta abbonamento</h2>
            <p className="text-xs text-muted-foreground mt-1">
              Puoi disattivare il rinnovo automatico solo dopo l&apos;attivazione dell&apos;abbonamento.
            </p>
          </div>
          <div className="text-xs text-muted-foreground">
            {subscriptionCurrentPeriodEnd && (
              <div>Prossimo addebito: {fmtDate(subscriptionCurrentPeriodEnd)}</div>
            )}
          </div>
        </div>

        <div className="mt-4">
          {data?.cancellation_requested ? (
            <div className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 text-center">
              <p className="font-semibold">Disdetta richiesta il {fmtDate(data.cancellation_requested_at)}</p>
              <p className="text-xs text-amber-700 mt-1">Potrai usare il servizio fino al termine del periodo già pagato</p>
            </div>
          ) : showCancelConfirm ? (
            <div className="rounded-md border border-destructive/30 bg-destructive/5 px-4 py-4 text-sm space-y-3">
              <p className="font-semibold text-destructive">Conferma disdetta abbonamento</p>
              <p className="text-muted-foreground text-xs">
                Potrai usare il servizio fino al termine del periodo già pagato. L&apos;accesso non verrà interrotto immediatamente.
              </p>
              <div className="flex gap-2">
                <Button
                  variant="destructive"
                  size="sm"
                  className="flex-1"
                  onClick={handleCancelSubscription}
                  disabled={cancelBusy || !isSubscriptionActive}
                >
                  {cancelBusy ? "Disdetta in corso..." : "Conferma disdetta"}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="flex-1"
                  onClick={() => setShowCancelConfirm(false)}
                  disabled={cancelBusy}
                >
                  Annulla
                </Button>
              </div>
            </div>
          ) : (
            <Button
              variant={isSubscriptionActive ? "destructive" : "outline"}
              className="w-full"
              onClick={() => setShowCancelConfirm(true)}
              disabled={cancelBusy || !isSubscriptionActive}
            >
              Disdici abbonamento
            </Button>
          )}
          {!isSubscriptionActive && !data?.cancellation_requested && (
            <p className="text-xs text-muted-foreground mt-2 text-center">
              Il tasto si attiva quando l&apos;abbonamento passa in stato attivo.
            </p>
          )}
        </div>
      </Card>
      )}

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
        {showRaw && import.meta.env.DEV && (
          <pre className="mt-3 text-xs bg-muted rounded-xl p-4 overflow-auto max-h-64 text-muted-foreground">
            {JSON.stringify(data, null, 2)}
          </pre>
        )}
      </div>
    </div>
  );
}
