import { useCallback, useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  Download, CreditCard, CheckCircle2, AlertCircle,
  Package, Building2, Clock, Calendar, RefreshCw, Database,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import { PasswordInput } from "@/components/PasswordInput";
import { Label } from "@/components/ui/label";
import {
  cancelPortalSubscription,
  downloadCustomerPortalBundle,
  getCustomerPortalMe,
  bookSetupSlot,
  confirmDataOk,
  getCustomerSourceDbState,
  getCustomerSourceDbRequestTemplate,
  parseCustomerSourceDbManagerResponse,
  saveCustomerSourceDbState,
  type SourceDbPortalState,
  type SourceDbRequestTemplate,
} from "@/lib/customerPortalApi";
import { planDisplayName, planDisplayPrice } from "@/lib/planConfig";
import { createSetupSession } from "@/lib/customerBillingApi";
import { useAuth } from "@/hooks/useAuth";
import { apiGet, apiPost } from "@/lib/apiClient";

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

type AccountTab =
  | "overview"
  | "profile"
  | "billing"
  | "installation"
  | "sourceDb"
  | "security";

const ACCOUNT_TABS: Array<{ key: AccountTab; label: string }> = [
  { key: "overview", label: "Panoramica" },
  { key: "profile", label: "Anagrafica" },
  { key: "billing", label: "Pagamento e abbonamento" },
  { key: "installation", label: "Installazione GreenBrain" },
  { key: "sourceDb", label: "Gestionale" },
  { key: "security", label: "Sicurezza" },
];

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
  vat_number?: string | null;
  address_line?: string | null;
  billing_email?: string | null;
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

interface LocalDbCredentials {
  status?: string;
  scope?: string;
  manual_postgres_install_required?: boolean;
  credentials_file?: string;
  postgres_host?: string;
  postgres_port?: string;
  postgres_db?: string;
  postgres_user?: string;
  postgres_password_present?: boolean;
  postgres_password_masked?: boolean;
  postgres_password?: string;
  database_url_present?: boolean;
  database_url_masked?: boolean;
  database_url?: string;
  tenant_code?: string;
  installation_id?: string;
  local_backend_port?: string;
  local_frontend_port?: string;
  data_storage?: {
    type?: string;
    container?: string;
    mount_path?: string;
    note?: string;
  };
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


function sourceDbStatusLabel(status: string | undefined | null) {
  const s = (status || "not_started").toLowerCase();
  if (s === "formal_validation_ok") return "Dati tecnici validati";
  if (s === "formal_validation_failed") return "Dati tecnici incompleti";
  if (s === "technical_test_pending") return "Test tecnico in attesa";
  if (s === "technical_test_failed") return "Test tecnico non superato";
  if (s === "technical_test_ok") return "Test tecnico superato";
  if (s === "response_saved") return "Risposta salvata";
  if (s === "request_ready") return "Richiesta pronta";
  return "Non configurato";
}

function sourceDbStatusBadge(status: string | undefined | null) {
  const s = (status || "not_started").toLowerCase();
  if (s === "technical_test_ok") return <Badge>Test tecnico OK</Badge>;
  if (s === "formal_validation_ok") return <Badge variant="secondary">Validazione formale OK</Badge>;
  if (s === "formal_validation_failed" || s === "technical_test_failed") {
    return <Badge variant="destructive">{sourceDbStatusLabel(s)}</Badge>;
  }
  return <Badge variant="outline">{sourceDbStatusLabel(s)}</Badge>;
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

  const [localDbCredentials, setLocalDbCredentials] = useState<LocalDbCredentials | null>(null);
  const [localDbPassword, setLocalDbPassword] = useState("");
  const [localDbRevealPassword, setLocalDbRevealPassword] = useState("");
  const [localDbDatabaseUrl, setLocalDbDatabaseUrl] = useState("");
  const [localDbBusy, setLocalDbBusy] = useState(false);
  const [localDbError, setLocalDbError] = useState<string | null>(null);
  const [localDbCopied, setLocalDbCopied] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchLocalDbCredentials() {
      try {
        setLocalDbError(null);
        const res = await apiGet("/api/v1/customer-runtime/local-db-credentials");
        if (!cancelled) setLocalDbCredentials(res);
      } catch (err) {
        if (!cancelled) {
          setLocalDbError(err instanceof Error ? err.message : "Credenziali tecniche locali non disponibili");
        }
      }
    }

    fetchLocalDbCredentials();
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleRevealLocalDbCredentials(e: React.FormEvent) {
    e.preventDefault();
    if (!localDbRevealPassword.trim()) {
      setLocalDbError("Inserisci la password del tuo account GreenBrain.");
      return;
    }

    try {
      setLocalDbBusy(true);
      setLocalDbError(null);
      const res = await apiPost("/api/v1/customer-runtime/local-db-credentials/reveal", {
        current_password: localDbRevealPassword,
      });
      setLocalDbCredentials(res);
      setLocalDbPassword(res?.postgres_password || "");
      setLocalDbDatabaseUrl(res?.database_url || "");
      setLocalDbRevealPassword("");
    } catch (err) {
      setLocalDbError(err instanceof Error ? err.message : "Impossibile mostrare le credenziali tecniche");
    } finally {
      setLocalDbBusy(false);
    }
  }

  async function copyLocalDbValue(label: string, value: string) {
    if (!value) return;
    try {
      await navigator.clipboard.writeText(value);
      setLocalDbCopied(label);
      window.setTimeout(() => setLocalDbCopied(null), 1800);
    } catch {
      setLocalDbError("Copia negli appunti non riuscita. Copia manualmente il valore.");
    }
  }

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

      <Card className="p-6">
        <div className="flex flex-col gap-1 mb-4">
          <h2 className="text-xl font-semibold">Credenziali tecniche database locale GreenBrain</h2>
          <p className="text-sm text-muted-foreground">
            PostgreSQL locale è gestito automaticamente da Docker. Non devi installare PostgreSQL manualmente.
            Queste credenziali servono solo per assistenza, backup o manutenzione tecnica.
          </p>
        </div>

        {localDbError && (
          <div className="rounded-md border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive mb-4">
            {localDbError}
          </div>
        )}

        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <p className="text-sm text-muted-foreground">Database</p>
            <p className="font-medium">{localDbCredentials?.postgres_db || "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Utente DB</p>
            <p className="font-medium">{localDbCredentials?.postgres_user || "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Host interno Docker</p>
            <p className="font-medium">{localDbCredentials?.postgres_host || "postgres"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Porta interna PostgreSQL</p>
            <p className="font-medium">{localDbCredentials?.postgres_port || "5432"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Porta backend locale</p>
            <p className="font-medium">{localDbCredentials?.local_backend_port || "8008"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Porta frontend locale</p>
            <p className="font-medium">{localDbCredentials?.local_frontend_port || "8088"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Tenant</p>
            <p className="font-medium">{localDbCredentials?.tenant_code || user?.tenant_code || "—"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Installazione</p>
            <p className="font-mono text-xs break-all">{localDbCredentials?.installation_id || "—"}</p>
          </div>
        </div>

        <div className="mt-5 rounded-xl border bg-muted/20 p-4">
          <p className="text-sm font-semibold mb-1">Dove sono salvati i dati locali?</p>
          <p className="text-sm text-muted-foreground">
            {localDbCredentials?.data_storage?.note ||
              "I dati PostgreSQL locali sono salvati nel volume Docker del runtime GreenBrain."}
          </p>
          <div className="grid gap-3 md:grid-cols-2 mt-3 text-sm">
            <div>
              <p className="text-muted-foreground">Container</p>
              <p className="font-medium">{localDbCredentials?.data_storage?.container || "greenbrain_local_postgres"}</p>
            </div>
            <div>
              <p className="text-muted-foreground">Percorso interno</p>
              <p className="font-mono text-xs">{localDbCredentials?.data_storage?.mount_path || "/var/lib/postgresql/data"}</p>
            </div>
          </div>
        </div>

        <form onSubmit={handleRevealLocalDbCredentials} className="mt-5 space-y-3">
          <div className="space-y-2">
            <Label htmlFor="local-db-reveal-password">Conferma password account GreenBrain</Label>
            <PasswordInput
              id="local-db-reveal-password"
              value={localDbRevealPassword}
              onChange={(e) => setLocalDbRevealPassword(e.target.value)}
              placeholder="Inserisci la password del tuo account"
              autoComplete="current-password"
            />
            <p className="text-xs text-muted-foreground">
              La password tecnica del DB viene mostrata solo dopo verifica della password account locale.
            </p>
          </div>

          <Button type="submit" variant="outline" disabled={localDbBusy}>
            {localDbBusy ? "Verifica..." : "Mostra credenziali tecniche"}
          </Button>
        </form>

        <div className="mt-5 space-y-3">
          <div className="rounded-xl border bg-background p-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Password DB</p>
                <p className="font-mono text-sm break-all">
                  {localDbPassword ? localDbPassword : localDbCredentials?.postgres_password_present ? "••••••••••••••••" : "Non disponibile"}
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => copyLocalDbValue("password", localDbPassword)}
                disabled={!localDbPassword}
              >
                {localDbCopied === "password" ? "Copiata" : "Copia password"}
              </Button>
            </div>
          </div>

          <div className="rounded-xl border bg-background p-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
              <div>
                <p className="text-sm text-muted-foreground">DATABASE_URL</p>
                <p className="font-mono text-xs break-all">
                  {localDbDatabaseUrl ? localDbDatabaseUrl : localDbCredentials?.database_url_present ? "••••••••••••••••" : "Non disponibile"}
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => copyLocalDbValue("database_url", localDbDatabaseUrl)}
                disabled={!localDbDatabaseUrl}
              >
                {localDbCopied === "database_url" ? "Copiata" : "Copia DATABASE_URL"}
              </Button>
            </div>
          </div>
        </div>

        <p className="text-xs text-muted-foreground mt-4">
          File tecnico locale: <code>overlay/env/customer-local.env</code>. Le credenziali non vengono salvate nel cloud.
        </p>
      </Card>
    </div>
  );
}


// ── main component ────────────────────────────────────────────────────────────


function formatDateTime(value?: string | null): string {
  if (!value) return "—";
  try {
    return new Date(value).toLocaleString("it-IT");
  } catch {
    return String(value);
  }
}

export default function CustomerPortalDashboard() {
  if (isLocalRuntimeHost()) {
    return <LocalRuntimeAccount />;
  }

  const [searchParams] = useSearchParams();
  const setupStatus = searchParams.get("setup");
  const billingStatus = searchParams.get("billing");

  const [data, setData] = useState<CustomerPortalProfile | null>(null);
  const [activeTab, setActiveTab] = useState<AccountTab>("overview");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefreshedAt, setLastRefreshedAt] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [showRaw, setShowRaw] = useState(false);
  const [securityCurrentPassword, setSecurityCurrentPassword] = useState("");
  const [securityNewPassword, setSecurityNewPassword] = useState("");
  const [securityConfirmPassword, setSecurityConfirmPassword] = useState("");
  const [securityBusy, setSecurityBusy] = useState(false);
  const [securityMessage, setSecurityMessage] = useState<string | null>(null);
  const [localPasswordSyncUrl, setLocalPasswordSyncUrl] = useState<string | null>(null);
  const [sourceDbState, setSourceDbState] = useState<SourceDbPortalState | null>(null);
  const [sourceDbBusy, setSourceDbBusy] = useState(false);
  const [sourceDbMessage, setSourceDbMessage] = useState<string | null>(null);
  const [sourceDbHost, setSourceDbHost] = useState("");
  const [sourceDbPort, setSourceDbPort] = useState("1433");
  const [sourceDbName, setSourceDbName] = useState("");
  const [sourceDbSchema, setSourceDbSchema] = useState("dbo");
  const [sourceDbClientCode, setSourceDbClientCode] = useState("");
  const [sourceDbViewName, setSourceDbViewName] = useState("GREENBRAIN_VIEW_SALES_RAW");
  const [sourceDbUsername, setSourceDbUsername] = useState("");
  const [sourceDbPassword, setSourceDbPassword] = useState("");
  const [sourceDbEncrypt, setSourceDbEncrypt] = useState(true);
  const [sourceDbTrustCert, setSourceDbTrustCert] = useState(true);
  const [sourceDbManagerEmail, setSourceDbManagerEmail] = useState("");
  const [sourceDbManagerResponse, setSourceDbManagerResponse] = useState("");
  const [sourceDbNotes, setSourceDbNotes] = useState("");
  const [sourceDbRequestTemplate, setSourceDbRequestTemplate] = useState<SourceDbRequestTemplate | null>(null);
  const [sourceDbRequestCopied, setSourceDbRequestCopied] = useState(false);
  const [sourceDbParseMissing, setSourceDbParseMissing] = useState<string[]>([]);
  const [sourceDbParseWarnings, setSourceDbParseWarnings] = useState<string[]>([]);

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

      try {
        const sourceDb = await getCustomerSourceDbState();
        setSourceDbState(sourceDb);
        const integration = sourceDb?.source_db_integration;
        if (integration) {
          setSourceDbHost(integration.db_host || "");
          setSourceDbPort(String(integration.db_port || 1433));
          setSourceDbName(integration.db_name || "");
          setSourceDbSchema(integration.db_schema || "dbo");
          setSourceDbClientCode(integration.source_client_code || profile?.tenant_code || "");
          setSourceDbViewName(integration.db_view_name || "GREENBRAIN_VIEW_SALES_RAW");
          setSourceDbUsername(integration.db_username || "");
          setSourceDbEncrypt(Boolean(integration.db_encrypt ?? true));
          setSourceDbTrustCert(Boolean(integration.db_trust_server_certificate ?? true));
          setSourceDbManagerEmail(integration.manager_contact_email || "");
          // SOURCE_DB_MANAGER_RESPONSE_PRESERVE_NONEMPTY: do not overwrite a reply
          // the user has pasted/typed while Source DB state refreshes.
          setSourceDbManagerResponse((prev) => prev.trim() ? prev : (integration.manager_response_raw_text || ""));
          setSourceDbNotes(integration.notes || "");
        } else {
          setSourceDbClientCode(profile?.tenant_code || "");
        }
      } catch {
        setSourceDbState(null);
      }

      setLastRefreshedAt(new Date().toISOString());
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

  useEffect(() => {
    if (!data?.platform_ready) return;

    const installed = (data.installed_release_version || "").trim();
    const downloaded = (data.last_downloaded_release_version || "").trim();

    if (!installed || !downloaded || installed === downloaded) return;

    let cancelled = false;
    let attempts = 0;
    const maxAttempts = 18; // 18 * 5s = 90s

    const interval = window.setInterval(async () => {
      if (cancelled) return;

      attempts += 1;
      await doFetch(true);

      if (attempts >= maxAttempts) {
        window.clearInterval(interval);
      }
    }, 5000);

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [
    data?.platform_ready,
    data?.installed_release_version,
    data?.last_downloaded_release_version,
    doFetch,
  ]);

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

  function openLocalPasswordSyncPage(): string {
    const url = "http://localhost:8088/local-sync/password?source=cloud-password-change";
    setLocalPasswordSyncUrl(url);

    try {
      const opened = window.open(url, "_blank", "noopener,noreferrer");
      if (opened) {
        return " Ho aperto la pagina di sincronizzazione locale. Se il browser la blocca, usa il pulsante qui sotto.";
      }
    } catch {
      // Browser may block popups after async password update. The visible link remains available.
    }

    return " Usa il pulsante qui sotto per sincronizzare subito GreenBrain locale; in ogni caso si allineerà automaticamente al prossimo controllo.";
  }

  // SOURCE_DB_TAB_REFRESH_ON_OPEN: keep Gestionale tab aligned with the dedicated Source DB API payload.
  useEffect(() => {
    if (activeTab !== "sourceDb") return;

    let cancelled = false;

    async function refreshSourceDbTabState() {
      try {
        const sourceDb = await getCustomerSourceDbState();
        if (cancelled) return;

        setSourceDbState(sourceDb);

        const integration = sourceDb?.source_db_integration;
        if (integration) {
          setSourceDbHost(integration.db_host || "");
          setSourceDbPort(String(integration.db_port || 1433));
          setSourceDbName(integration.db_name || "");
          setSourceDbSchema(integration.db_schema || "dbo");
          setSourceDbClientCode(integration.source_client_code || data?.tenant_code || "");
          setSourceDbViewName(integration.db_view_name || "GREENBRAIN_VIEW_SALES_RAW");
          setSourceDbUsername(integration.db_username || "");
          setSourceDbEncrypt(Boolean(integration.db_encrypt ?? true));
          setSourceDbTrustCert(Boolean(integration.db_trust_server_certificate ?? true));
          setSourceDbManagerEmail(integration.manager_contact_email || "");
          // SOURCE_DB_MANAGER_RESPONSE_PRESERVE_NONEMPTY: do not overwrite a reply
          // the user has pasted/typed while Source DB state refreshes.
          setSourceDbManagerResponse((prev) => prev.trim() ? prev : (integration.manager_response_raw_text || ""));
          setSourceDbNotes(integration.notes || "");
        } else {
          setSourceDbClientCode(data?.tenant_code || "");
        }
      } catch (err) {
        if (!cancelled) {
          setSourceDbMessage(err instanceof Error ? err.message : "Impossibile aggiornare stato collegamento gestionale");
        }
      }
    }

    refreshSourceDbTabState();

    return () => {
      cancelled = true;
    };
  }, [activeTab, data?.tenant_code]);

  async function handleSaveSourceDb(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSourceDbMessage(null);

    try {
      setSourceDbBusy(true);
      const res = await saveCustomerSourceDbState({
        db_type: "sqlserver",
        db_host: sourceDbHost.trim(),
        db_port: Number(sourceDbPort || 1433),
        db_name: sourceDbName.trim(),
        db_schema: sourceDbSchema.trim() || "dbo",
        source_client_code: sourceDbClientCode.trim() || data?.tenant_code || undefined,
        db_view_name: sourceDbViewName.trim() || "GREENBRAIN_VIEW_SALES_RAW",
        db_username: sourceDbUsername.trim(),
        password: sourceDbPassword.trim() || undefined,
        db_encrypt: sourceDbEncrypt,
        db_trust_server_certificate: sourceDbTrustCert,
        manager_contact_email: sourceDbManagerEmail.trim() || undefined,
        manager_response_raw_text: sourceDbManagerResponse.trim() || undefined,
        notes: sourceDbNotes.trim() || undefined,
      });

      setSourceDbState(res);
      setSourceDbPassword("");
      setSourceDbMessage(
        res.db_integration_status === "formal_validation_ok"
          ? "Dati gestionali salvati e validati formalmente. Il test tecnico verrà eseguito dal computer collegato alla rete del gestionale."
          : "Dati gestionali salvati. Completa i campi mancanti prima del test tecnico."
      );
      await doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore salvataggio collegamento gestionale");
    } finally {
      setSourceDbBusy(false);
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

  async function handleChangePassword(e: React.FormEvent) {
    e.preventDefault();

    const currentPassword = securityCurrentPassword.trim();
    const newPassword = securityNewPassword;
    const confirmPassword = securityConfirmPassword;

    setSecurityMessage(null);
    setError(null);

    if (!currentPassword) {
      setError("Inserisci la password attuale.");
      return;
    }

    if (newPassword.length < 8) {
      setError("La nuova password deve contenere almeno 8 caratteri.");
      return;
    }

    if (newPassword !== confirmPassword) {
      setError("La conferma password non coincide.");
      return;
    }

    try {
      setSecurityBusy(true);
      const res = await apiPost("/api/v1/auth/change-password", {
        current_password: currentPassword,
        new_password: newPassword,
      });

      setSecurityCurrentPassword("");
      setSecurityNewPassword("");
      setSecurityConfirmPassword("");

      let syncText = "";
      setLocalPasswordSyncUrl(null);

      if (res?.password_last_sync_status === "pending") {
        syncText = openLocalPasswordSyncPage();
      }

      if (!syncText) {
        syncText = " GreenBrain locale è già allineato. Non ci sono aggiornamenti password da applicare.";
      }

      setSecurityMessage(`Password aggiornata correttamente.${syncText}`);
      await doFetch(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore cambio password");
    } finally {
      setSecurityBusy(false);
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
  const installedVersion = data?.installed_release_version || null;
  const firstDownloadedVersion = data?.first_downloaded_release_version || null;
  const firstDownloadedAt = data?.first_downloaded_at || null;
  const lastDownloadedVersion = data?.last_downloaded_release_version || null;
  const lastDownloadedAt = data?.last_downloaded_at || null;
  const hasNeverDownloaded = !lastDownloadedAt;
  const subscriptionCancelAtPeriodEnd = Boolean(data?.subscription_cancel_at_period_end);
  const subscriptionCurrentPeriodEnd = data?.subscription_current_period_end || null;
  const subscriptionActivatedAt = data?.subscription_activated_at || null;
  const isSubscriptionActive = (data?.subscription_status || "").toLowerCase() === "active";
  async function handleGenerateSourceDbRequest() {
    try {
      setSourceDbBusy(true);
      setSourceDbMessage(null);
      setSourceDbRequestCopied(false);

      const template = await getCustomerSourceDbRequestTemplate();
      setSourceDbRequestTemplate(template);
      setSourceDbMessage("Richiesta pronta: copiala e inviala al referente del gestionale.");
    } catch (err) {
      setSourceDbMessage(err instanceof Error ? err.message : "Impossibile generare la richiesta per il gestionale");
    } finally {
      setSourceDbBusy(false);
    }
  }

  async function handleCopySourceDbRequest() {
    if (!sourceDbRequestTemplate) {
      setSourceDbMessage("Genera prima la richiesta per il gestore DB.");
      return;
    }

    const text = `Oggetto: ${sourceDbRequestTemplate.subject}\n\n${sourceDbRequestTemplate.body}`;

    try {
      if (navigator?.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
      } else {
        const textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.focus();
        textarea.select();
        document.execCommand("copy");
        document.body.removeChild(textarea);
      }

      setSourceDbRequestCopied(true);
      setSourceDbMessage("Richiesta copiata. Ora puoi inviarla al referente del gestionale.");
    } catch {
      setSourceDbMessage("Impossibile copiare automaticamente. Seleziona e copia manualmente il testo della richiesta.");
    }
  }

  async function handleParseSourceDbManagerResponse() {
    const raw = sourceDbManagerResponse.trim();

    if (!raw) {
      setSourceDbMessage("Incolla prima la risposta del gestore DB / gestionale.");
      return;
    }

    try {
      setSourceDbBusy(true);
      setSourceDbMessage(null);
      setSourceDbParseMissing([]);
      setSourceDbParseWarnings([]);

      const result = await parseCustomerSourceDbManagerResponse(raw);
      const suggested = result.suggested_payload || {};

      if (suggested.db_host) setSourceDbHost(String(suggested.db_host));
      if (suggested.db_port) setSourceDbPort(String(suggested.db_port));
      if (suggested.db_name) setSourceDbName(String(suggested.db_name));
      if (suggested.db_schema) setSourceDbSchema(String(suggested.db_schema));
      if (suggested.source_client_code) setSourceDbClientCode(String(suggested.source_client_code));
      if (suggested.db_view_name) setSourceDbViewName(String(suggested.db_view_name));
      if (suggested.db_username) setSourceDbUsername(String(suggested.db_username));
      if (typeof suggested.db_encrypt === "boolean") setSourceDbEncrypt(suggested.db_encrypt);
      if (typeof suggested.db_trust_server_certificate === "boolean") {
        setSourceDbTrustCert(suggested.db_trust_server_certificate);
      }
      if (suggested.manager_response_raw_text) {
        setSourceDbManagerResponse(String(suggested.manager_response_raw_text));
      }

      setSourceDbParseMissing(result.missing || []);
      setSourceDbParseWarnings(result.warnings || []);

      if (result.status === "parse_ok") {
        setSourceDbMessage(
          result.password_detected
            ? "Risposta analizzata e campi precompilati. La password non è stata copiata: inseriscila solo nel campo Password DB."
            : "Risposta analizzata e campi tecnici precompilati. Controlla i dati e salva.",
        );
      } else if (result.status === "parse_partial") {
        setSourceDbMessage("Risposta analizzata parzialmente: completa i campi mancanti e poi salva.");
      } else {
        setSourceDbMessage("Non sono riuscito a leggere automaticamente la risposta: compila i campi manualmente.");
      }
    } catch (err) {
      setSourceDbMessage(err instanceof Error ? err.message : "Impossibile analizzare la risposta del gestore DB");
    } finally {
      setSourceDbBusy(false);
    }
  }

  const sourceDbIntegration = sourceDbState?.source_db_integration || null;
  const sourceDbStatus = sourceDbState?.db_integration_status
    || sourceDbIntegration?.formal_validation_status
    || data?.db_integration_status
    || "not_started";
  const sourceDbMissing = Array.isArray(sourceDbIntegration?.formal_validation_result?.missing)
    ? sourceDbIntegration?.formal_validation_result?.missing || []
    : [];
  const sourceDbWarnings = Array.isArray(sourceDbIntegration?.formal_validation_result?.warnings)
    ? sourceDbIntegration?.formal_validation_result?.warnings || []
    : [];

  const sourceDbTechnicalResult = (sourceDbIntegration?.technical_test_result || {}) as Record<string, unknown>;
  const sourceDbTextValue = (value: unknown): string | null => {
    if (value === null || value === undefined) return null;
    const text = String(value).trim();
    return text.length > 0 ? text : null;
  };
  const sourceDbFailureCode = sourceDbTextValue(sourceDbTechnicalResult.failure_code);
  const sourceDbFailureMessage = sourceDbTextValue(sourceDbTechnicalResult.failure_message);
  const sourceDbActionRequired = sourceDbTextValue(sourceDbTechnicalResult.action_required);
  const sourceDbLastError = sourceDbIntegration?.last_error_report || null;
  const sourceDbLastErrorAt = sourceDbIntegration?.last_error_at || null;

  const platformReady = Boolean(data?.platform_ready);
  const installationStatusLabel = data?.installation_status_label || (
    platformReady ? "Piattaforma attiva" : "Installazione non ancora completata"
  );

  const hasUpdateAvailable = Boolean(
    latestAvailableVersion &&
    lastDownloadedVersion &&
    latestAvailableVersion !== lastDownloadedVersion
  );

  const downloadedButNotInstalled = Boolean(
    platformReady &&
    installedVersion &&
    lastDownloadedVersion &&
    installedVersion !== lastDownloadedVersion
  );

  const bundleButtonIsPrimary = Boolean(
    bundleDownloadEnabled && (hasNeverDownloaded || hasUpdateAvailable)
  );

  const nextActionIsDownloadUpdate = Boolean(
    bundleDownloadEnabled &&
    hasUpdateAvailable &&
    latestAvailableVersion
  );

  const nextActionIsDownloadedPendingInstall = Boolean(
    bundleDownloadEnabled &&
    downloadedButNotInstalled &&
    lastDownloadedVersion
  );

  const nextActionUpdateButtonLabel = nextActionIsDownloadedPendingInstall && lastDownloadedVersion
    ? `Aggiorna ora alla versione ${lastDownloadedVersion}`
    : latestAvailableVersion
    ? `Scarica versione ${latestAvailableVersion}`
    : "Scarica aggiornamento";

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
      done: platformReady,
      label: "Setup e installazione",
      detail: platformReady
        ? installationStatusLabel
        : "Completa il wizard locale: la piattaforma sarà attiva dopo il primo heartbeat healthy.",
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
      done: platformReady,
    },
    { key: "data", label: "Dati confermati", done: Boolean(data?.data_validated_at) },
    { key: "subscription", label: "Abbonamento", done: isSubscriptionActive },
  ];

  const completedStepCount = compactSteps.filter((step) => step.done).length;
  const firstIncompleteStepIndex = compactSteps.findIndex((step) => !step.done);
  const activeStepIndex = firstIncompleteStepIndex === -1 ? compactSteps.length - 1 : firstIncompleteStepIndex;

  const nextActionTitle =
    nextActionIsDownloadedPendingInstall
      ? "Aggiorna GreenBrain"
    : nextActionIsDownloadUpdate
      ? "Scarica aggiornamento"
    : platformReady
      ? "Apri la piattaforma"
    : phase === "no_payment"
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
    nextActionIsDownloadedPendingInstall
      ? `Hai già scaricato la versione ${lastDownloadedVersion}. Completa l'aggiornamento dal computer dove è installato GreenBrain.`
    : nextActionIsDownloadUpdate
      ? `È disponibile la versione ${latestAvailableVersion}. Scarica il nuovo bundle per aggiornare GreenBrain.`
    : platformReady
      ? "La tua installazione locale è collegata correttamente. Puoi accedere alle sezioni operative GreenBrain."
    : phase === "no_payment"
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

      <div className="rounded-2xl border bg-card p-2 shadow-sm">
        <div className="grid grid-cols-2 md:grid-cols-6 gap-2">
          {ACCOUNT_TABS.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`rounded-xl px-3 py-2 text-xs md:text-sm font-medium transition-colors ${
                activeTab === tab.key
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-muted hover:text-foreground"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {activeTab === "profile" && (
        <Card className="p-6 border-primary/10">
          <div className="flex items-start gap-3 mb-5">
            <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0">
              <Building2 className="w-5 h-5 text-primary" />
            </div>
            <div>
              <h2 className="font-semibold text-lg leading-tight">Anagrafica</h2>
              <p className="text-xs text-muted-foreground mt-1">
                Dati account e aziendali salvati nel cloud GreenBrain.
              </p>
            </div>
          </div>

          <Separator className="my-4" />

          <div className="grid md:grid-cols-2 gap-4 text-sm">
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Azienda</p>
              <p className="font-semibold">{data?.company_name || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Partita IVA</p>
              <p className="font-semibold">{data?.vat_number || "Non indicata"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4 md:col-span-2">
              <p className="text-xs text-muted-foreground mb-1">Indirizzo</p>
              <p className="font-semibold">{data?.address_line || "Non indicato"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Città</p>
              <p className="font-semibold">{data?.city || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Paese</p>
              <p className="font-semibold">{data?.country || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Referente</p>
              <p className="font-semibold">{data?.contact_name || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Telefono referente</p>
              <p className="font-semibold">{data?.contact_phone || "Non indicato"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Email referente</p>
              <p className="font-semibold break-all">{data?.contact_email || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Email account</p>
              <p className="font-semibold break-all">{data?.portal_user_email || "—"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Email fatturazione</p>
              <p className="font-semibold break-all">{data?.billing_email || "Non indicata"}</p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Tenant</p>
              <p className="font-mono text-xs break-all">{data?.tenant_code || "—"}</p>
            </div>
          </div>

          <div className="rounded-xl border border-dashed bg-muted/20 px-4 py-3 text-xs text-muted-foreground mt-5">
            La modifica dei dati anagrafici verrà abilitata nel prossimo step con salvataggio sicuro su Supabase cloud.
          </div>
        </Card>
      )}

      {activeTab === "billing" && (
        <div className="space-y-5">
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
        </div>
      )}

      {activeTab === "installation" && (
        <div className="space-y-5">
          {/* Runtime status */}
          <Card className="p-6 border-primary/10">
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3 mb-4">
              <div>
                <h2 className="font-semibold">Runtime locale</h2>
                <p className="text-xs text-muted-foreground mt-1">
                  {lastRefreshedAt
                    ? `Ultimo controllo: ${fmtDateTime(lastRefreshedAt)}`
                    : "Stato letto dal cloud GreenBrain"}
                </p>
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => doFetch(true)}
                disabled={refreshing}
              >
                <RefreshCw className={`w-4 h-4 mr-2 ${refreshing ? "animate-spin" : ""}`} />
                {refreshing ? "Aggiornamento..." : "Aggiorna stato installazione"}
              </Button>
            </div>
            <div className="grid sm:grid-cols-3 gap-3">
              <div className="rounded-xl border bg-muted/20 p-4">
                <p className="text-xs text-muted-foreground mb-1">Stato piattaforma</p>
                <Badge variant={platformReady ? "default" : "outline"}>
                  {installationStatusLabel}
                </Badge>
              </div>
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
                <p className="text-xs text-muted-foreground mb-1">Versione installata</p>
                <p className="font-semibold text-sm">{installedVersion || "Non registrata"}</p>
              </div>
              <div className="rounded-xl border bg-muted/20 p-4">
                <p className="text-xs text-muted-foreground mb-1">Agent locale</p>
                <p className="font-semibold text-sm">{data?.runtime_local_agent_version || "—"}</p>
              </div>
              <div className="rounded-xl border bg-muted/20 p-4">
                <p className="text-xs text-muted-foreground mb-1">Installazione</p>
                <p className="font-mono text-xs break-all">
                  {data?.latest_installation_id || "Non registrata"}
                </p>
              </div>
            </div>
          </Card>

            {/* Local account access */}
            <Card className="p-6 border-primary/10 bg-primary/5">
              <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-5">
                <div className="space-y-2">
                  <h2 className="font-semibold">Account locale su questo computer</h2>
                  <p className="text-sm text-muted-foreground">
                    Le credenziali tecniche del database locale sono disponibili solo dal runtime GreenBrain installato su questo computer.
                    Per sicurezza non vengono salvate né mostrate dal cloud.
                  </p>
                  <p className="text-xs text-muted-foreground">
                    Apri l’account locale per visualizzare database, utente tecnico, password DB, DATABASE_URL e posizione dei dati locali dopo conferma della password account.
                  </p>
                </div>
                <div className="flex flex-col sm:flex-row lg:flex-col gap-3 lg:min-w-[220px]">
                  <Button asChild>
                    <a href="http://localhost:8088/account?source=cloud-account" target="_blank" rel="noreferrer">
                      Apri account locale
                    </a>
                  </Button>
                  <Button variant="outline" asChild>
                    <a href="http://localhost:8088/dashboard?source=cloud-account" target="_blank" rel="noreferrer">
                      Apri dashboard locale
                    </a>
                  </Button>
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
                  {platformReady
                    ? "Bundle disponibile per reinstallare o aggiornare GreenBrain quando necessario."
                    : "Release GreenBrain pronta per completare setup e installazione."}
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

            {downloadedButNotInstalled && (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 mb-4">
                <p className="font-semibold">Aggiornamento scaricato ma non installato</p>
                <p className="mt-1 text-xs">
                  Hai scaricato la versione {lastDownloadedVersion}, ma il runtime locale risulta ancora alla versione {installedVersion}.
                  Completa l’aggiornamento dal computer dove è installato GreenBrain.
                </p>
              </div>
            )}

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
                {platformReady
                  ? "Scarica di nuovo il bundle solo se devi reinstallare o aggiornare GreenBrain."
                  : "Usa questo file durante la sessione remota di setup per completare GreenBrain."}
              </p>
            )}
          </Card>
        </div>
      )}


      {activeTab === "sourceDb" && (
        <Card className="p-6 border-primary/10">
          <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between mb-5">
            <div className="flex items-start gap-3">
              <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0">
                <Database className="w-5 h-5 text-primary" />
              </div>
              <div>
                <h2 className="font-semibold text-lg leading-tight">Collegamento gestionale</h2>
                <p className="text-xs text-muted-foreground mt-1">
                  Inserisci i dati tecnici ricevuti dal gestore del database. La password viene cifrata e non viene mai mostrata nel portale.
                </p>
              </div>
            </div>
            <div className="flex-shrink-0">
              {sourceDbStatusBadge(sourceDbStatus)}
            </div>
          </div>

          {sourceDbMessage && (
            <div className="rounded-xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm mb-4">
              {sourceDbMessage}
            </div>
          )}

          <div className="grid gap-4 md:grid-cols-3 mb-5">
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Stato formale</p>
              <p className="font-semibold">
                {sourceDbStatusLabel(sourceDbIntegration?.formal_validation_status || sourceDbStatus)}
              </p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Test tecnico</p>
              <p className="font-semibold">
                {sourceDbStatusLabel(sourceDbIntegration?.technical_test_status || "not_started")}
              </p>
            </div>
            <div className="rounded-xl border bg-muted/20 p-4">
              <p className="text-xs text-muted-foreground mb-1">Password DB</p>
              <p className="font-semibold">
                {sourceDbIntegration?.db_password_set ? "Salvata e cifrata" : "Non salvata"}
              </p>
            </div>
          </div>

          {(sourceDbFailureCode || sourceDbFailureMessage || sourceDbLastError || sourceDbActionRequired) && (
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900 mb-5">
              <p className="font-semibold mb-2">Problema tecnico Source DB</p>
              <div className="space-y-1 text-xs">
                {sourceDbFailureCode && (
                  <p><span className="font-semibold">Codice errore tecnico:</span> {sourceDbFailureCode}</p>
                )}
                {sourceDbFailureMessage && (
                  <p><span className="font-semibold">Errore tecnico:</span> {sourceDbFailureMessage}</p>
                )}
                {sourceDbLastError && (
                  <p><span className="font-semibold">Ultimo errore:</span> {sourceDbLastError}</p>
                )}
                {sourceDbLastErrorAt && (
                  <p><span className="font-semibold">Ultimo errore il:</span> {formatDateTime(sourceDbLastErrorAt)}</p>
                )}
              </div>
              {sourceDbActionRequired && (
                <div className="mt-3 rounded-lg border border-amber-200 bg-white/70 px-3 py-2">
                  <p className="text-xs font-semibold mb-1">Azione richiesta</p>
                  <p className="text-xs whitespace-pre-wrap">{sourceDbActionRequired}</p>
                </div>
              )}
            </div>
          )}

          {(sourceDbMissing.length > 0 || sourceDbWarnings.length > 0) && (
            <div className="grid gap-3 md:grid-cols-2 mb-5">
              {sourceDbMissing.length > 0 && (
                <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm">
                  <p className="font-semibold mb-2">Dati mancanti</p>
                  <ul className="list-disc pl-5 space-y-1">
                    {sourceDbMissing.map((item) => <li key={item}>{item}</li>)}
                  </ul>
                </div>
              )}
              {sourceDbWarnings.length > 0 && (
                <div className="rounded-xl border bg-amber-50 border-amber-200 p-4 text-sm text-amber-900">
                  <p className="font-semibold mb-2">Avvisi</p>
                  <ul className="list-disc pl-5 space-y-1">
                    {sourceDbWarnings.map((item) => <li key={item}>{item}</li>)}
                  </ul>
                </div>
              )}
            </div>
          )}

          <div className="rounded-xl border bg-muted/20 p-4 space-y-4">
            <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
              <div>
                <p className="text-sm font-semibold">1. Richiedi i dati al referente del gestionale</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Genera un testo già pronto da copiare e inviare al tecnico del gestionale / database.
                </p>
              </div>
              <div className="flex flex-col gap-2 sm:flex-row">
                <Button
                  type="button"
                  variant="outline"
                  onClick={handleGenerateSourceDbRequest}
                  disabled={sourceDbBusy}
                >
                  {sourceDbBusy ? "Generazione..." : "Genera richiesta"}
                </Button>
                <Button
                  type="button"
                  variant="secondary"
                  onClick={handleCopySourceDbRequest}
                  disabled={!sourceDbRequestTemplate || sourceDbBusy}
                >
                  {sourceDbRequestCopied ? "Copiata" : "Copia richiesta"}
                </Button>
              </div>
            </div>

            {sourceDbRequestTemplate && (
              <div className="space-y-2">
                <div className="rounded-lg border bg-background px-3 py-2">
                  <p className="text-xs font-semibold text-muted-foreground">Oggetto email</p>
                  <p className="text-sm">{sourceDbRequestTemplate.subject}</p>
                </div>
                <pre className="max-h-72 overflow-auto rounded-lg border bg-background p-3 text-xs whitespace-pre-wrap font-sans">
                  {sourceDbRequestTemplate.body}
                </pre>
              </div>
            )}
          </div>

          <form onSubmit={handleSaveSourceDb} className="space-y-5">
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="source-db-host">Server SQL / istanza</Label>
                <Input
                  id="source-db-host"
                  value={sourceDbHost}
                  onChange={(e) => setSourceDbHost(e.target.value)}
                  placeholder="SERVERGREEN\\FLORINFO"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-port">Porta</Label>
                <Input
                  id="source-db-port"
                  value={sourceDbPort}
                  onChange={(e) => setSourceDbPort(e.target.value)}
                  placeholder="1433"
                  inputMode="numeric"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-name">Database</Label>
                <Input
                  id="source-db-name"
                  value={sourceDbName}
                  onChange={(e) => setSourceDbName(e.target.value)}
                  placeholder="AZIEN001"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-schema">Schema</Label>
                <Input
                  id="source-db-schema"
                  value={sourceDbSchema}
                  onChange={(e) => setSourceDbSchema(e.target.value)}
                  placeholder="dbo"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-client-code">Codice cliente / tenant</Label>
                <Input
                  id="source-db-client-code"
                  value={sourceDbClientCode}
                  onChange={(e) => setSourceDbClientCode(e.target.value)}
                  placeholder={data?.tenant_code || "codice cliente"}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-view">Vista dati vendite</Label>
                <Input
                  id="source-db-view"
                  value={sourceDbViewName}
                  onChange={(e) => setSourceDbViewName(e.target.value)}
                  placeholder="GREENBRAIN_VIEW_SALES_RAW"
                />
                <p className="text-xs text-muted-foreground">
                  Standard consigliato: GREENBRAIN_VIEW_SALES_RAW.
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-username">Utente SQL read-only</Label>
                <Input
                  id="source-db-username"
                  value={sourceDbUsername}
                  onChange={(e) => setSourceDbUsername(e.target.value)}
                  placeholder="greenbrain_reader"
                  autoComplete="username"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-password">
                  Password DB {sourceDbIntegration?.db_password_set ? "(lascia vuota per non modificarla)" : ""}
                </Label>
                <PasswordInput
                  id="source-db-password"
                  value={sourceDbPassword}
                  onChange={(e) => setSourceDbPassword(e.target.value)}
                  placeholder={sourceDbIntegration?.db_password_set ? "Password già salvata" : "Password utente read-only"}
                  autoComplete="new-password"
                />
              </div>
            </div>

            <div className="grid gap-3 md:grid-cols-2">
              <label className="flex items-start gap-3 rounded-xl border bg-muted/20 p-4 text-sm">
                <input
                  type="checkbox"
                  checked={sourceDbEncrypt}
                  onChange={(e) => setSourceDbEncrypt(e.target.checked)}
                  className="mt-1"
                />
                <span>
                  <span className="font-semibold block">Encrypt attivo</span>
                  <span className="text-muted-foreground">Consigliato per SQL Server Driver 18.</span>
                </span>
              </label>

              <label className="flex items-start gap-3 rounded-xl border bg-muted/20 p-4 text-sm">
                <input
                  type="checkbox"
                  checked={sourceDbTrustCert}
                  onChange={(e) => setSourceDbTrustCert(e.target.checked)}
                  className="mt-1"
                />
                <span>
                  <span className="font-semibold block">Trust server certificate</span>
                  <span className="text-muted-foreground">Utile in rete locale con certificato non pubblico.</span>
                </span>
              </label>
            </div>

            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="source-db-manager-email">Email referente gestionale</Label>
                <Input
                  id="source-db-manager-email"
                  value={sourceDbManagerEmail}
                  onChange={(e) => setSourceDbManagerEmail(e.target.value)}
                  placeholder="tecnico@gestionale.it"
                  type="email"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="source-db-notes">Note interne</Label>
                <Input
                  id="source-db-notes"
                  value={sourceDbNotes}
                  onChange={(e) => setSourceDbNotes(e.target.value)}
                  placeholder="Es. dati ricevuti dal tecnico il..."
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="source-db-manager-response">Risposta del gestore DB / gestionale</Label>
              <textarea
                id="source-db-manager-response"
                value={sourceDbManagerResponse}
                onChange={(e) => setSourceDbManagerResponse(e.target.value)}
                className="min-h-[110px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                placeholder="Incolla qui server, database, vista, utente read-only ed eventuali note su VPN/rete."
              />
            </div>

            <div className="rounded-xl border bg-muted/20 p-4 space-y-3">
              <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                <div>
                  <p className="text-sm font-semibold">2. Analizza la risposta ricevuta</p>
                  <p className="text-xs text-muted-foreground mt-1">
                    Incolla la risposta del tecnico e lascia che GreenBrain precompili i campi tecnici.
                  </p>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  onClick={handleParseSourceDbManagerResponse}
                  disabled={sourceDbBusy || !sourceDbManagerResponse.trim()}
                >
                  {sourceDbBusy ? "Analisi..." : "Analizza risposta"}
                </Button>
              </div>

              {(sourceDbParseMissing.length > 0 || sourceDbParseWarnings.length > 0) && (
                <div className="grid gap-3 md:grid-cols-2">
                  {sourceDbParseMissing.length > 0 && (
                    <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
                      <p className="font-semibold mb-1">Campi da completare</p>
                      <ul className="list-disc pl-4 space-y-1">
                        {sourceDbParseMissing.map((item) => <li key={item}>{item}</li>)}
                      </ul>
                    </div>
                  )}

                  {sourceDbParseWarnings.length > 0 && (
                    <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-xs text-primary">
                      <p className="font-semibold mb-1">Note di sicurezza</p>
                      <ul className="list-disc pl-4 space-y-1">
                        {sourceDbParseWarnings.map((item) => <li key={item}>{item}</li>)}
                      </ul>
                    </div>
                  )}
                </div>
              )}
            </div>

            {sourceDbIntegration?.formal_validation_report && (
              <div className="rounded-xl border bg-muted/20 p-4">
                <p className="text-sm font-semibold mb-2">Report validazione formale</p>
                <pre className="whitespace-pre-wrap text-xs text-muted-foreground font-sans">
                  {sourceDbIntegration.formal_validation_report}
                </pre>
              </div>
            )}

            <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <p className="text-xs text-muted-foreground">
                Il test tecnico sulla raggiungibilità SQL Server verrà eseguito successivamente dal computer nella rete del gestionale.
              </p>
              <Button type="submit" disabled={sourceDbBusy}>
                {sourceDbBusy ? "Salvataggio..." : "Salva collegamento gestionale"}
              </Button>
            </div>
          </form>
        </Card>
      )}

      {activeTab === "security" && (
        <Card className="p-6 border-primary/10">
          <div className="flex flex-col gap-1 mb-5">
            <h2 className="font-semibold text-lg">Sicurezza</h2>
            <p className="text-sm text-muted-foreground">
              Modifica la password dell&apos;account cloud GreenBrain. La nuova password verrà poi sincronizzata con l&apos;installazione locale.
            </p>
          </div>

          <form onSubmit={handleChangePassword} className="space-y-4 max-w-xl">
            <div className="space-y-1.5">
              <Label htmlFor="securityCurrentPassword" className="text-xs">Password attuale</Label>
              <PasswordInput
                id="securityCurrentPassword"
                autoComplete="current-password"
                value={securityCurrentPassword}
                onChange={(e) => setSecurityCurrentPassword(e.target.value)}
                disabled={securityBusy}
                required
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="securityNewPassword" className="text-xs">Nuova password</Label>
              <PasswordInput
                id="securityNewPassword"
                autoComplete="new-password"
                value={securityNewPassword}
                onChange={(e) => setSecurityNewPassword(e.target.value)}
                disabled={securityBusy}
                minLength={8}
                required
              />
              <p className="text-xs text-muted-foreground">Minimo 8 caratteri.</p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="securityConfirmPassword" className="text-xs">Conferma nuova password</Label>
              <PasswordInput
                id="securityConfirmPassword"
                autoComplete="new-password"
                value={securityConfirmPassword}
                onChange={(e) => setSecurityConfirmPassword(e.target.value)}
                disabled={securityBusy}
                minLength={8}
                required
              />
            </div>

            {securityMessage && (
              <div className="rounded-xl border border-primary/20 bg-primary/5 px-4 py-3 text-sm text-primary space-y-2">
                <p>{securityMessage}</p>
                {localPasswordSyncUrl && (
                  <div>
                    <a
                      href={localPasswordSyncUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex"
                    >
                      <Button type="button" size="sm" variant="outline">
                        Sincronizza GreenBrain locale ora
                      </Button>
                    </a>
                  </div>
                )}
              </div>
            )}

            <div className="rounded-xl border bg-muted/30 px-4 py-3 text-xs text-muted-foreground">
              Per sicurezza la password può essere modificata solo da questo account cloud. Il runtime locale riceverà l&apos;hash aggiornato tramite sincronizzazione controllata.
            </div>

            <Button type="submit" disabled={securityBusy}>
              {securityBusy ? "Aggiornamento password..." : "Aggiorna password"}
            </Button>
          </form>
        </Card>
      )}

      {activeTab === "overview" && (
      <>
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

            {(nextActionIsDownloadUpdate || nextActionIsDownloadedPendingInstall) && (
              <Button
                variant="default"
                onClick={handleDownloadBundle}
                disabled={!bundleDownloadEnabled || downloading}
              >
                <Download className="w-4 h-4 mr-2" />
                {downloading ? "Download in corso..." : nextActionUpdateButtonLabel}
              </Button>
            )}

            {platformReady && !nextActionIsDownloadUpdate && !nextActionIsDownloadedPendingInstall && (
              <Button asChild>
                <Link to="/dashboard">
                  <CheckCircle2 className="w-4 h-4 mr-2" />
                  Apri GreenBrain
                </Link>
              </Button>
            )}

            {!platformReady && phase === "no_payment" && (
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

            {!platformReady && bundleDownloadEnabled && (phase === "slot_confirmed" || phase === "active") && (
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
          <div className="flex justify-between items-center">
            <span className="text-muted-foreground">Stato piattaforma</span>
            <Badge variant={platformReady ? "default" : "outline"}>
              {installationStatusLabel}
            </Badge>
          </div>
          {installedVersion && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Versione installata</span>
              <span>{installedVersion}</span>
            </div>
          )}
          {latestAvailableVersion && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Versione disponibile</span>
              <span>{latestAvailableVersion}</span>
            </div>
          )}
          {lastDownloadedVersion && (
            <div className="flex justify-between items-center">
              <span className="text-muted-foreground">Ultima scaricata</span>
              <span>{lastDownloadedVersion}</span>
            </div>
          )}
        </div>
      </Card>


      </div>


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


      </>
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
