import { useCallback, useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import {
  getCustomerById,
  sendRelease,
  requestCustomerCancellation,
  markDeliverySent,
  confirmCustomerSlot,
  updateCustomerOnboardingStatus,
  activateCustomerSubscription,
  forceActivateCustomerSubscription,
  createCustomerPasswordResetLink,
  DELIVERY_STATUS_LABELS,
  type CustomerOpsItem,
  type PasswordResetLinkResponse,
} from "@/lib/customerOpsApi";
import { planDisplayName, planDisplayPrice } from "@/lib/planConfig";
import { LATEST_RELEASE, customerHealth } from "@/lib/opsConfig";

// ── helpers ───────────────────────────────────────────────────────────────────

const STATUS_COLORS: Record<string, { bg: string; color: string }> = {
  active:                  { bg: "#dcfce7", color: "#166534" },
  data_validated:          { bg: "#dcfce7", color: "#166534" },
  installed:               { bg: "#dcfce7", color: "#166534" },
  slot_requested:          { bg: "#fef9c3", color: "#854d0e" },
  data_validation_pending: { bg: "#fef9c3", color: "#854d0e" },
  checkout_started:        { bg: "#fef9c3", color: "#854d0e" },
  slot_confirmed:          { bg: "#ede9fe", color: "#5b21b6" },
  setup_in_progress:       { bg: "#ede9fe", color: "#5b21b6" },
  failed:                  { bg: "#fee2e2", color: "#991b1b" },
  error:                   { bg: "#fee2e2", color: "#991b1b" },
  past_due:                { bg: "#fee2e2", color: "#991b1b" },
  incomplete:              { bg: "#fee2e2", color: "#991b1b" },
};

function badge(status: string | null | undefined) {
  const s = (status || "—").toLowerCase();
  const c = STATUS_COLORS[s] ?? { bg: "#f3f4f6", color: "#6b7280" };
  return (
    <span style={{
      background: c.bg, color: c.color,
      borderRadius: 4, padding: "2px 8px",
      fontSize: 12, fontWeight: 600,
      display: "inline-block", whiteSpace: "nowrap",
    }}>
      {status || "—"}
    </span>
  );
}

function fmtDt(iso: string | null | undefined, mode: "date" | "datetime" = "date") {
  if (!iso) return null;
  try {
    return mode === "datetime"
      ? new Date(iso).toLocaleString("it-IT")
      : new Date(iso).toLocaleDateString("it-IT");
  } catch { return iso; }
}

const NEXT_ONBOARDING_STATUS: Record<string, string> = {
  slot_requested:          "slot_confirmed",
  slot_confirmed:          "setup_in_progress",
  setup_in_progress:       "data_validation_pending",
};

const ONBOARDING_STEPS: { key: string; label: string }[] = [
  { key: "slot_requested",          label: "Slot richiesto" },
  { key: "slot_confirmed",          label: "Slot confermato" },
  { key: "setup_in_progress",       label: "Setup in corso" },
  { key: "data_validation_pending", label: "Validazione dati" },
  { key: "data_validated",          label: "Dati validati" },
];

function OnboardingStepper({ item }: { item: CustomerOpsItem }) {
  const isActive = (item.subscription_status || "").toLowerCase() === "active";
  const allSteps = [...ONBOARDING_STEPS.map((s) => s.label), "Abbonamento attivo"];
  const currentIdx = isActive
    ? allSteps.length
    : ONBOARDING_STEPS.findIndex((s) => s.key === item.onboarding_status);

  return (
    <div style={stepperBox}>
      {allSteps.flatMap((label, i) => {
        const done = i < currentIdx || isActive;
        const current = !isActive && currentIdx === i;
        const circle = (
          <div key={`step-${i}`} style={{ display: "flex", flexDirection: "column" as const, alignItems: "center", minWidth: 52 }}>
            <div style={{
              width: 26, height: 26, borderRadius: "50%",
              background: done ? "#dcfce7" : current ? "#ede9fe" : "#f9fafb",
              border: `2px solid ${done ? "#86efac" : current ? "#a78bfa" : "#e5e7eb"}`,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 10, fontWeight: 800,
              color: done ? "#16a34a" : current ? "#7c3aed" : "#9ca3af",
            }}>
              {done ? "✓" : i + 1}
            </div>
            <div style={{ fontSize: 8, fontWeight: current ? 700 : 500, marginTop: 3, color: done ? "#16a34a" : current ? "#7c3aed" : "#9ca3af", textAlign: "center" as const, lineHeight: 1.2, maxWidth: 52 }}>
              {label}
            </div>
          </div>
        );
        if (i < allSteps.length - 1) {
          return [circle, <div key={`line-${i}`} style={{ flex: 1, height: 2, background: done ? "#86efac" : "#e5e7eb", minWidth: 8, marginTop: 12 }} />];
        }
        return [circle];
      })}
    </div>
  );
}

// ── sub-components ────────────────────────────────────────────────────────────

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={sectionBox}>
      <div style={sectionTitle}>{title}</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px 24px" }}>
        {children}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  if (value === null || value === undefined || value === "") return null;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      <span style={{ fontSize: 10, fontWeight: 700, color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.04em" }}>
        {label}
      </span>
      <span style={{ fontSize: 13, color: "#111827" }}>{value}</span>
    </div>
  );
}

// ── page ──────────────────────────────────────────────────────────────────────

function StatusPill({ label, value, raw }: { label: string; value: string | null | undefined; raw?: boolean }) {
  return (
    <div style={{ textAlign: "center" as const }}>
      <div style={{ fontSize: 9, color: "#9ca3af", fontWeight: 700, textTransform: "uppercase" as const, letterSpacing: "0.04em", marginBottom: 3 }}>
        {label}
      </div>
      {raw
        ? <span style={{ fontSize: 12, fontWeight: 600, color: "#374151" }}>{value || "—"}</span>
        : badge(value)
      }
    </div>
  );
}

function ActionGroup({ emoji, title, children }: { emoji: string; title: string; children: React.ReactNode }) {
  return (
    <div style={actionGroupBox}>
      <div style={actionGroupLabelStyle}>{emoji} {title}</div>
      {children}
    </div>
  );
}

export default function CustomerDetail() {
  const { customerId } = useParams<{ customerId: string }>();
  const [item, setItem] = useState<CustomerOpsItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionMsg, setActionMsg] = useState<{ type: "ok" | "err"; text: string } | null>(null);
  const [slotScheduled, setSlotScheduled] = useState("");
  const [forceModal, setForceModal] = useState(false);
  const [forceConfirmed, setForceConfirmed] = useState(false);
  const [forceText, setForceText] = useState("");
  const [forceBusy, setForceBusy] = useState(false);
  const [passwordResetBusy, setPasswordResetBusy] = useState(false);
  const [passwordResetLink, setPasswordResetLink] = useState<PasswordResetLinkResponse | null>(null);
  const [passwordResetCopied, setPasswordResetCopied] = useState(false);

  const load = useCallback(() => {
    if (!customerId) return;
    setLoading(true);
    setError(null);
    getCustomerById(customerId)
      .then((found) => setItem(found))
      .catch((err) => {
        const msg = err instanceof Error ? err.message : "Errore caricamento";
        setError(msg.includes("customer_not_found") ? "Cliente non trovato." : msg);
      })
      .finally(() => setLoading(false));
  }, [customerId]);

  useEffect(() => { load(); }, [load]);

  async function run(action: () => Promise<string>) {
    setBusy(true);
    setActionMsg(null);
    try {
      const msg = await action();
      setActionMsg({ type: "ok", text: msg });
      load();
    } catch (err) {
      setActionMsg({ type: "err", text: err instanceof Error ? err.message : "Errore" });
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return (
      <div style={page}>
        <BackLink />
        <p style={{ color: "#6b7280", marginTop: 32 }}>Caricamento...</p>
      </div>
    );
  }

  if (error || !item) {
    return (
      <div style={page}>
        <BackLink />
        <div style={errorBox}>{error || "Cliente non trovato."}</div>
      </div>
    );
  }

  const planName       = planDisplayName(item.subscription_plan);
  const planPrice      = planDisplayPrice(item.subscription_plan);
  const nextStatus     = NEXT_ONBOARDING_STATUS[item.onboarding_status] ?? null;
  const slotAlreadyConfirmed = Boolean(item.setup_slot_confirmed_at || item.setup_slot_scheduled_for);
  const canShowConfirmSlot = Boolean(item.setup_slot_requested_at && !slotAlreadyConfirmed);
  const canConfirmSlot = canShowConfirmSlot && slotScheduled.length > 0;
  const canActivateSub = item.onboarding_status === "data_validated" && item.payment_method_saved === true;
  const canCancel = ["active", "trialing", "past_due", "incomplete"].includes(
    (item.subscription_status || "").toLowerCase(),
  );
  const availableRelease = item.latest_available_release_version || LATEST_RELEASE;
  const releaseAligned = Boolean(item.last_downloaded_release_version && item.last_downloaded_release_version === availableRelease);
  const downloadedButNotInstalled = Boolean(
    item.platform_ready &&
    item.installed_release_version &&
    item.last_downloaded_release_version &&
    item.installed_release_version !== item.last_downloaded_release_version
  );
  const effectiveDbIntegrationStatus =
    item.db_integration_status === "not_started" && item.data_validated_at
      ? "validated"
      : item.db_integration_status;

  const effectiveInstallStatus =
    item.delivery_install_status === "installed"
      ? "installed"
      : item.install_status === "installed"
      ? "installed"
      : item.setup_slot_confirmed_at
      ? "scheduled"
      : item.install_status;

  const installationProcessStatus = item.installation_status_label || (
    item.installation_status === "downloaded"
      ? "Bundle scaricato, installazione non ancora collegata"
      : item.installation_status === "registered"
      ? "Runtime registrato, in attesa stato healthy"
      : item.onboarding_status === "setup_in_progress"
      ? "Setup in corso"
      : slotAlreadyConfirmed
      ? "Slot confermato"
      : null
  );

  const installationProcessDone = Boolean(item.platform_ready);

  const effectiveInstalledRelease =
    item.installed_release_version ||
    (item.delivery_install_status === "installed"
      ? (item.delivery_assigned_release_version || null)
      : null);

  async function handleGeneratePasswordResetLink() {
    if (!item) return;

    setPasswordResetBusy(true);
    setActionMsg(null);
    setPasswordResetLink(null);
    setPasswordResetCopied(false);

    try {
      const res = await createCustomerPasswordResetLink(item.customer_id);
      setPasswordResetLink(res);
      setActionMsg({ type: "ok", text: `Link reset password generato per ${res.email}` });
    } catch (err) {
      setActionMsg({ type: "err", text: err instanceof Error ? err.message : "Errore generazione link reset password" });
    } finally {
      setPasswordResetBusy(false);
    }
  }

  async function handleCopyPasswordResetLink() {
    if (!passwordResetLink?.reset_url) return;

    try {
      await navigator.clipboard.writeText(passwordResetLink.reset_url);
      setPasswordResetCopied(true);
      window.setTimeout(() => setPasswordResetCopied(false), 1800);
      setActionMsg({ type: "ok", text: "Link reset password copiato negli appunti" });
    } catch {
      setActionMsg({ type: "err", text: "Impossibile copiare il link automaticamente. Copialo manualmente dal campo." });
    }
  }

  async function handleForceActivate() {
    setForceBusy(true);
    setActionMsg(null);
    try {
      await forceActivateCustomerSubscription(item.customer_id);
      setItem((prev) => prev ? {
        ...prev,
        subscription_status: "active",
        subscription_cancel_at_period_end: false,
      } : prev);
      setActionMsg({ type: "ok", text: `Abbonamento attivato (override) per ${item.company_name}` });
      setForceModal(false);
      load();
    } catch (err) {
      setActionMsg({ type: "err", text: err instanceof Error ? err.message : "Errore" });
      setForceModal(false);
    } finally {
      setForceBusy(false);
    }
  }

  return (
    <div style={page}>
      {forceModal && item && (
        <ForceActivateModal
          onClose={() => setForceModal(false)}
          onConfirm={handleForceActivate}
          confirmed={forceConfirmed}
          setConfirmed={setForceConfirmed}
          forceText={forceText}
          setForceText={setForceText}
          busy={forceBusy}
        />
      )}
      <BackLink />

      {/* ── header ── */}
      <div style={headerBox}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <h1 style={{ margin: 0, fontSize: 24, fontWeight: 800, lineHeight: 1.2 }}>{item.company_name}</h1>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 8, flexWrap: "wrap" as const }}>
            {item.tenant_code && <span style={tenantTag}>{item.tenant_code}</span>}
            {item.contact_email && <span style={{ fontSize: 12, color: "#6b7280" }}>{item.contact_email}</span>}
            {item.created_at && <span style={{ fontSize: 11, color: "#9ca3af" }}>Iscritto il {fmtDt(item.created_at)}</span>}
          </div>
        </div>
        <div style={{ display: "flex", gap: 16, flexWrap: "wrap" as const, alignItems: "flex-start" }}>
          <StatusPill label="Onboarding" value={item.onboarding_status} />
          <StatusPill label="Abbonamento" value={item.subscription_status} />
          {item.subscription_plan && <StatusPill label="Piano" value={item.subscription_plan} raw />}
          {(() => {
            const h = customerHealth(item);
            return (
              <div style={{ textAlign: "center" as const }}>
                <div style={{ fontSize: 9, color: "#9ca3af", fontWeight: 700, textTransform: "uppercase" as const, letterSpacing: "0.04em", marginBottom: 3 }}>Salute</div>
                <span style={{ background: h.bg, color: h.color, borderRadius: 4, padding: "2px 8px", fontSize: 12, fontWeight: 600, whiteSpace: "nowrap" as const }}>{h.label}</span>
              </div>
            );
          })()}
        </div>
      </div>

      {/* ── checklist processo in evidenza ── */}

      {/* ── action feedback ── */}
      {actionMsg && (
        <div style={actionMsg.type === "ok" ? feedbackOk : feedbackErr}>
          {actionMsg.type === "ok" ? "✓ " : "✗ "}{actionMsg.text}
        </div>
      )}

      {/* ── operator process checklist ── */}
      <div style={processChecklistBox}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 16, alignItems: "flex-start", marginBottom: 14 }}>
          <div>
            <div style={processChecklistTitle}>Checklist processo cliente</div>
            <div style={{ fontSize: 12, color: "#6b7280", marginTop: 3 }}>
              Stato operativo del percorso: registrazione, pagamento, setup, download, validazione e abbonamento.
            </div>
          </div>
          {badge(item.onboarding_status)}
        </div>

        <div style={processChecklistGrid}>
          {([
            { done: Boolean(item.created_at), label: "Account creato", detail: fmtDt(item.created_at, "datetime") },
            { done: Boolean(item.payment_method_saved), label: "Pagamento salvato", detail: item.payment_method_saved ? `${item.payment_method_brand?.toUpperCase() || "Carta"} ••••${item.payment_method_last4 || ""}` : null },
            { done: Boolean(item.setup_slot_requested_at), label: "Slot richiesto", detail: fmtDt(item.setup_slot_requested_at, "datetime") },
            { done: Boolean(item.setup_slot_confirmed_at || item.setup_slot_scheduled_for), label: "Slot confermato", detail: fmtDt(item.setup_slot_scheduled_for || item.setup_slot_confirmed_at, "datetime") },
            { done: Boolean(item.last_downloaded_at), label: "Bundle scaricato", detail: item.last_downloaded_at ? `${item.last_downloaded_release_version || "—"} · ${fmtDt(item.last_downloaded_at, "datetime")}` : null },
            { done: installationProcessDone, label: "Installazione", detail: installationProcessStatus },
            { done: Boolean(item.data_validated_at), label: "Dati validati", detail: fmtDt(item.data_validated_at, "datetime") },
            { done: (item.subscription_status || "").toLowerCase() === "active", label: "Abbonamento attivo", detail: item.subscription_activated_at ? fmtDt(item.subscription_activated_at, "datetime") : item.subscription_status },
          ] as { done: boolean; label: string; detail: React.ReactNode }[]).map(({ done, label, detail }, i) => (
            <div key={i} style={processChecklistItem}>
              <div style={{
                width: 24,
                height: 24,
                borderRadius: "50%",
                flexShrink: 0,
                background: done ? "#dcfce7" : "#f9fafb",
                border: `2px solid ${done ? "#86efac" : "#e5e7eb"}`,
                color: done ? "#16a34a" : "#9ca3af",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontWeight: 900,
                fontSize: 12,
              }}>
                {done ? "✓" : i + 1}
              </div>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: done ? "#166534" : "#374151" }}>
                  {label}
                </div>
                {detail && (
                  <div style={{ fontSize: 11, color: "#6b7280", marginTop: 2, wordBreak: "break-word" as const }}>
                    {detail}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ── prossima azione consigliata ── */}
      <div style={nextActionBox}>
        <div>
          <div style={{ fontSize: 11, fontWeight: 900, color: "#1e3a8a", textTransform: "uppercase" as const, letterSpacing: "0.06em" }}>
            Prossima azione consigliata
          </div>
          <div style={{ fontSize: 14, fontWeight: 700, color: "#111827", marginTop: 4 }}>
            {canShowConfirmSlot
              ? "Confermare la sessione di setup richiesta dal cliente"
              : nextStatus
              ? `Avanzare onboarding a ${nextStatus}`
              : canActivateSub && item.subscription_status !== "active"
              ? "Attivare l’abbonamento cliente"
              : !releaseAligned
              ? "Inviare la release aggiornata"
              : canCancel && !item.cancellation_requested
              ? "Monitorare abbonamento e servizio attivo"
              : "Processo cliente sotto controllo"}
          </div>

        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" as const, alignItems: "center" }}>
          {canShowConfirmSlot && (
            <span style={nextActionBadge}>Vai alla card Slot setup</span>
          )}
          {nextStatus && !canShowConfirmSlot && (
            <button
              onClick={() => run(async () => {
                await updateCustomerOnboardingStatus(item.customer_id, nextStatus);
                return `Stato aggiornato: ${nextStatus}`;
              })}
              disabled={busy}
              style={busy ? btnDisabled : btnPrimary}
            >
              Avanza a {nextStatus}
            </button>
          )}
          {canActivateSub && item.subscription_status !== "active" && !nextStatus && (
            <button
              onClick={async () => {
                setBusy(true);
                setActionMsg(null);
                try {
                  await activateCustomerSubscription(item.customer_id);
                  setItem((prev) => prev ? {
                    ...prev,
                    subscription_status: "active",
                    subscription_cancel_at_period_end: false,
                  } : prev);
                  setActionMsg({ type: "ok", text: `Abbonamento attivato per ${item.company_name}` });
                  load();
                } catch (err) {
                  setActionMsg({ type: "err", text: err instanceof Error ? err.message : "Errore" });
                } finally {
                  setBusy(false);
                }
              }}
              disabled={busy}
              style={busy ? btnDisabled : btnPrimary}
            >
              Attiva abbonamento
            </button>
          )}
          {!releaseAligned && !canShowConfirmSlot && !nextStatus && (
            <button
              onClick={() => run(async () => {
                const res = await sendRelease(item.customer_id, availableRelease);
                const label = DELIVERY_STATUS_LABELS[res.delivery_status] ?? res.delivery_status;
                return `Release ${res.assigned_release_version} inviata — delivery: ${label}`;
              })}
              disabled={busy}
              style={busy ? btnDisabled : btnPrimary}
            >
              Invia release {availableRelease}
            </button>
          )}
        </div>
      </div>

      {/* ── info grid (2 col) ── */}
      <div style={infoGrid}>

        {/* Left: identity → payment */}
        <div style={{ display: "flex", flexDirection: "column" as const, gap: 12 }}>
          <Section title="Contatti">
            <Row label="Referente" value={item.contact_name} />
            <Row label="Email" value={item.contact_email} />
            <Row label="Telefono" value={item.contact_phone} />
            <Row label="Customer ID" value={<code style={{ fontSize: 11 }}>{item.customer_id}</code>} />
            <Row label="Creato il" value={fmtDt(item.created_at)} />
            <Row label="Aggiornato il" value={fmtDt(item.updated_at, "datetime")} />

            
            <div style={{ ...inlineActionBox, gridColumn: "1 / -1" }}>
              <div style={inlineActionTitle}>Sicurezza account</div>
              <div style={{ display: "flex", flexDirection: "column" as const, gap: 8 }}>
                <div style={{ fontSize: 11, color: "#6b7280", lineHeight: 1.4 }}>
                  Genera un link temporaneo per reimpostare la password dell&apos;utente cliente. Il link non cambia la password finché il cliente non completa il reset.
                </div>
            
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" as const, alignItems: "center" }}>
                  <button
                    onClick={handleGeneratePasswordResetLink}
                    disabled={busy || passwordResetBusy}
                    style={busy || passwordResetBusy ? btnDisabled : btnPrimary}
                  >
                    {passwordResetBusy ? "Generazione..." : "Genera link reset password"}
                  </button>
            
                  {passwordResetLink?.expires_at && (
                    <span style={{ fontSize: 11, color: "#6b7280" }}>
                      Valido fino al {fmtDt(passwordResetLink.expires_at, "datetime")}
                    </span>
                  )}
                </div>
            
                {passwordResetLink?.reset_url && (
                  <div style={resetLinkBox}>
                    <div style={{ fontSize: 10, fontWeight: 800, color: "#374151", textTransform: "uppercase" as const, letterSpacing: "0.04em" }}>
                      Link generato per {passwordResetLink.email}
                    </div>
            
                    <code style={resetLinkCode}>{passwordResetLink.reset_url}</code>
            
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap" as const, alignItems: "center" }}>
                      <button
                        onClick={handleCopyPasswordResetLink}
                        style={passwordResetCopied ? btnCopied : btn}
                        title={passwordResetCopied ? "Link copiato" : "Copia link reset password"}
                      >
                        {passwordResetCopied ? "✓ Copiato" : "📋 Copia link"}
                      </button>
            
                      {passwordResetLink.token_hint && (
                        <span style={{ fontSize: 11, color: "#6b7280" }}>
                          Hint token: {passwordResetLink.token_hint}
                        </span>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </Section>

          <Section title="Pagamento e abbonamento">
            <Row label="Piano" value={planName !== "—" ? `${planName}${planPrice ? ` — ${planPrice}` : ""}` : null} />
            <Row label="Stato abbonamento" value={badge(item.subscription_status)} />
            <Row
              label="Metodo di pagamento"
              value={
                item.payment_method_saved
                  ? `${item.payment_method_brand?.toUpperCase() || "Carta"} ••••${item.payment_method_last4 || ""}`
                  : "Carta non salvata"
              }
            />
            {item.cancellation_requested && (
              <Row label="Disdetta" value={<span style={{ color: "#d97706", fontWeight: 600, fontSize: 11 }}>Richiesta il {fmtDt(item.cancellation_requested_at, "datetime")}</span>} />
            )}
            {item.subscription_activated_at && (
              <Row label="Pagamento attivato il" value={fmtDt(item.subscription_activated_at, "datetime")} />
            )}
            {item.subscription_current_period_end && item.subscription_cancel_at_period_end && (
              <Row label="Servizio disponibile fino al" value={fmtDt(item.subscription_current_period_end, "datetime")} />
            )}
            {item.subscription_current_period_end && !item.subscription_cancel_at_period_end && (
              <Row label="Prossimo addebito" value={fmtDt(item.subscription_current_period_end, "datetime")} />
            )}
            {item.subscription_cancel_at_period_end !== null && item.subscription_cancel_at_period_end !== undefined && (
              <Row label="Rinnovo automatico" value={item.subscription_cancel_at_period_end ? "Disattivato" : "Attivo"} />
            )}

            <div style={inlineActionBox}>
              <div style={inlineActionTitle}>Azioni abbonamento</div>
              {item.subscription_status === "active" ? (
                <>
                  <span style={{ fontSize: 12, color: "#16a34a", fontWeight: 700 }}>✓ Abbonamento attivo</span>
                  {item.cancellation_requested ? (
                    <div style={{ background: "#fef3c7", border: "1px solid #fcd34d", borderRadius: 6, padding: "7px 10px", fontSize: 11, marginTop: 6 }}>
                      <strong style={{ color: "#92400e" }}>Disdetta richiesta</strong>
                      <div style={{ color: "#b45309", marginTop: 2 }}>{fmtDt(item.cancellation_requested_at, "datetime") || "—"}</div>
                    </div>
                  ) : (
                    <button
                      onClick={() => run(async () => {
                        await requestCustomerCancellation(item.customer_id);
                        return "Richiesta disdetta registrata";
                      })}
                      disabled={busy || !canCancel}
                      style={{ ...(canCancel && !busy ? btn : btnDisabled), marginTop: 6 }}
                    >
                      Richiedi disdetta
                    </button>
                  )}
                </>
              ) : (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" as const, alignItems: "center" }}>
                  <button
                    onClick={async () => {
                      setBusy(true);
                      setActionMsg(null);
                      try {
                        await activateCustomerSubscription(item.customer_id);
                        setItem((prev) => prev ? {
                          ...prev,
                          subscription_status: "active",
                          subscription_cancel_at_period_end: false,
                        } : prev);
                        setActionMsg({ type: "ok", text: `Abbonamento attivato per ${item.company_name}` });
                        load();
                      } catch (err) {
                        setActionMsg({ type: "err", text: err instanceof Error ? err.message : "Errore" });
                      } finally {
                        setBusy(false);
                      }
                    }}
                    disabled={busy || !canActivateSub}
                    style={canActivateSub && !busy ? btnPrimary : btnDisabled}
                  >
                    Attiva abbonamento
                  </button>
                  <button
                    onClick={() => { setForceModal(true); setForceConfirmed(false); setForceText(""); }}
                    disabled={busy || item.subscription_status === "active"}
                    style={{ ...btn, fontSize: 11, color: "#b45309", borderColor: "#fcd34d" }}
                  >
                    Override
                  </button>
                  {!canActivateSub && (
                    <span style={{ fontSize: 10, color: "#9ca3af" }}>
                      Richiede dati validati e metodo pagamento
                    </span>
                  )}
                </div>
              )}
            </div>
          </Section>
        </div>

        {/* Right: slot → onboarding → delivery */}
        <div style={{ display: "flex", flexDirection: "column" as const, gap: 12 }}>
          <Section title="Slot setup">
            <Row label="Data preferita" value={item.setup_slot_preferred_date} />
            <Row
              label="Fascia oraria"
              value={
                item.setup_slot_preferred_time === "morning" ? "Mattina"
                : item.setup_slot_preferred_time === "afternoon" ? "Pomeriggio"
                : item.setup_slot_preferred_time || null
              }
            />
            <Row label="Richiesto il" value={fmtDt(item.setup_slot_requested_at, "datetime")} />
            <Row label="Confermato il" value={fmtDt(item.setup_slot_confirmed_at, "datetime")} />
            <Row label="Schedulato per" value={fmtDt(item.setup_slot_scheduled_for, "datetime")} />

            <div style={inlineActionBox}>
              <div style={inlineActionTitle}>Azione slot</div>
              {slotAlreadyConfirmed ? (
                <span style={{ fontSize: 12, color: "#16a34a", fontWeight: 700 }}>✓ Slot confermato</span>
              ) : canShowConfirmSlot ? (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" as const, alignItems: "center" }}>
                  <input
                    type="datetime-local"
                    value={slotScheduled}
                    onChange={(e) => setSlotScheduled(e.target.value)}
                    style={inputStyle}
                  />
                  <button
                    onClick={() => run(async () => {
                      await confirmCustomerSlot(item.customer_id, slotScheduled);
                      return `Slot confermato: ${slotScheduled}`;
                    })}
                    disabled={busy || !canConfirmSlot}
                    style={canConfirmSlot && !busy ? btnPrimary : btnDisabled}
                  >
                    Conferma slot
                  </button>
                </div>
              ) : item.setup_slot_preferred_date ? (
                <span style={{ fontSize: 12, color: "#6b7280" }}>Preferenza ricevuta, in attesa conferma operatore</span>
              ) : (
                <span style={{ fontSize: 12, color: "#9ca3af" }}>Nessuna azione disponibile</span>
              )}
            </div>
          </Section>


          <Section title="Runtime locale">
            <Row label="Stato piattaforma" value={item.installation_status_label || (item.platform_ready ? "Piattaforma attiva" : "Non ancora attiva")} />
            <Row label="Stato connessione" value={badge(item.runtime_connection_status)} />
            <Row label="Ultimo heartbeat" value={fmtDt(item.last_runtime_heartbeat_at, "datetime")} />
            <Row label="Installation ID" value={item.latest_installation_id ? <code style={{ fontSize: 11 }}>{item.latest_installation_id}</code> : "Non registrata"} />
            <Row label="Release installata" value={item.installed_release_version || effectiveInstalledRelease || null} />
            <Row label="Runtime pubblico" value={item.runtime_public_backend_url || null} />
            <Row label="Agent locale" value={item.runtime_local_agent_version || null} />
          </Section>

          <Section title="Download e release">
            <Row
              label="Ultima release disponibile"
              value={
                <span style={{
                  display: "inline-block",
                  fontSize: 12,
                  fontWeight: 700,
                  color: "#166534",
                  background: "#dcfce7",
                  border: "1px solid #86efac",
                  borderRadius: 5,
                  padding: "3px 10px",
                }}>
                  {availableRelease}
                </span>
              }
            />
            {!item.last_downloaded_release_version && (
              <Row
                label="Stato aggiornamento"
                value={
                  <span style={{
                    display: "inline-block",
                    fontSize: 12,
                    fontWeight: 700,
                    color: "#6b7280",
                    background: "#f3f4f6",
                    border: "1px solid #e5e7eb",
                    borderRadius: 5,
                    padding: "3px 10px",
                  }}>
                    Mai scaricato
                  </span>
                }
              />
            )}
            {item.last_downloaded_release_version && item.last_downloaded_release_version !== availableRelease && (
              <Row
                label="Stato aggiornamento"
                value={
                  <span style={{
                    display: "inline-block",
                    fontSize: 12,
                    fontWeight: 700,
                    color: "#92400e",
                    background: "#fef3c7",
                    border: "1px solid #fcd34d",
                    borderRadius: 5,
                    padding: "3px 10px",
                  }}>
                    Nuova versione da scaricare
                  </span>
                }
              />
            )}
            {downloadedButNotInstalled && (
              <Row
                label="Stato aggiornamento"
                value={
                  <span style={{
                    display: "inline-block",
                    fontSize: 12,
                    fontWeight: 700,
                    color: "#92400e",
                    background: "#fef3c7",
                    border: "1px solid #fcd34d",
                    borderRadius: 5,
                    padding: "3px 10px",
                  }}>
                    Scaricata, da installare
                  </span>
                }
              />
            )}
            {item.last_downloaded_release_version === availableRelease && !downloadedButNotInstalled && (
              <Row
                label="Stato aggiornamento"
                value={
                  <span style={{
                    display: "inline-block",
                    fontSize: 12,
                    fontWeight: 700,
                    color: "#166534",
                    background: "#dcfce7",
                    border: "1px solid #86efac",
                    borderRadius: 5,
                    padding: "3px 10px",
                  }}>
                    Aggiornata
                  </span>
                }
              />
            )}
            <Row label="Release installata" value={item.installed_release_version || effectiveInstalledRelease || null} />
            <Row label="Prima scaricata" value={item.first_downloaded_release_version} />
            <Row label="Primo download il" value={fmtDt(item.first_downloaded_at, "datetime")} />
            <Row label="Ultima scaricata" value={item.last_downloaded_release_version} />
            <Row label="Ultimo download il" value={fmtDt(item.last_downloaded_at, "datetime")} />
            <Row label="Bundle generato il" value={fmtDt(item.bundle_generated_at, "datetime")} />

          </Section>
        </div>
      </div>

      <div style={{ marginTop: 8 }}>
        <Link to="/customers" style={{ fontSize: 13, color: "#6b7280" }}>
          ← Torna alla lista clienti
        </Link>
      </div>
    </div>
  );
}

function ForceActivateModal({
  onClose,
  onConfirm,
  confirmed,
  setConfirmed,
  forceText,
  setForceText,
  busy,
}: {
  onClose: () => void;
  onConfirm: () => void;
  confirmed: boolean;
  setConfirmed: (v: boolean) => void;
  forceText: string;
  setForceText: (v: string) => void;
  busy: boolean;
}) {
  return (
    <div style={{
      position: "fixed", inset: 0, background: "rgba(0,0,0,0.45)",
      display: "flex", alignItems: "center", justifyContent: "center",
      zIndex: 999,
    }}>
      <div style={{
        background: "white", borderRadius: 10, padding: "28px 32px",
        maxWidth: 420, width: "90%", boxShadow: "0 8px 32px rgba(0,0,0,0.18)",
      }}>
        <div style={{ fontSize: 18, fontWeight: 800, color: "#92400e", marginBottom: 10 }}>
          ⚠️ Override attivazione abbonamento
        </div>
        <p style={{ fontSize: 13, color: "#374151", marginBottom: 14, lineHeight: 1.5 }}>
          Stai per attivare l&apos;abbonamento <strong>senza</strong> che il cliente abbia confermato i propri dati.
          Questa azione bypassa il controllo di validazione e crea una sottoscrizione Stripe immediatamente.
        </p>
        <label style={{ display: "flex", alignItems: "flex-start", gap: 8, fontSize: 12, color: "#1f2937", cursor: "pointer", marginBottom: 12 }}>
          <input
            type="checkbox"
            checked={confirmed}
            onChange={(e) => setConfirmed(e.target.checked)}
            style={{ marginTop: 2, flexShrink: 0 }}
          />
          Confermo di voler attivare l&apos;abbonamento senza la conferma dati del cliente
        </label>
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontSize: 11, color: "#6b7280", marginBottom: 6 }}>
            Digita <strong>CONFERMO</strong> per abilitare l&apos;override
          </div>
          <input
            type="text"
            value={forceText}
            onChange={(e) => setForceText(e.target.value)}
            style={{ ...inputStyle, width: "100%" }}
            placeholder="CONFERMO"
          />
        </div>
        <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
          <button onClick={onClose} disabled={busy} style={btn}>Annulla</button>
          <button
            onClick={onConfirm}
            disabled={!confirmed || forceText.trim() !== "CONFERMO" || busy}
            style={!confirmed || busy ? btnDisabled : {
              ...btnPrimary, background: "#fef3c7", borderColor: "#fcd34d", color: "#92400e",
            }}
          >
            {busy ? "Attivazione..." : "Conferma override"}
          </button>
        </div>
      </div>
    </div>
  );
}

function BackLink() {
  return (
    <div style={{ marginBottom: 20 }}>
      <Link to="/customers" style={{ fontSize: 13, color: "#6b7280", textDecoration: "none" }}>
        ← Clienti
      </Link>
    </div>
  );
}

// ── styles ────────────────────────────────────────────────────────────────────

const nextActionBox: React.CSSProperties = {
  display: "flex",
  justifyContent: "space-between",
  gap: 16,
  alignItems: "center",
  background: "#eff6ff",
  border: "1px solid #bfdbfe",
  borderRadius: 12,
  padding: "16px 20px",
  marginBottom: 18,
  boxShadow: "0 1px 2px rgba(30, 64, 175, 0.06)",
};

const nextActionBadge: React.CSSProperties = {
  display: "inline-block",
  fontSize: 12,
  fontWeight: 700,
  color: "#1e40af",
  background: "#dbeafe",
  border: "1px solid #93c5fd",
  borderRadius: 999,
  padding: "5px 10px",
};

const inlineActionBox: React.CSSProperties = {
  gridColumn: "1 / -1",
  borderTop: "1px solid #e5e7eb",
  marginTop: 4,
  paddingTop: 10,
};

const inlineActionTitle: React.CSSProperties = {
  fontSize: 10,
  fontWeight: 900,
  color: "#6b7280",
  textTransform: "uppercase",
  letterSpacing: "0.06em",
  marginBottom: 6,
};

const processChecklistBox: React.CSSProperties = {
  background: "linear-gradient(180deg, #f8fafc 0%, #ffffff 100%)",
  border: "1px solid #dbeafe",
  borderRadius: 12,
  padding: "18px 22px",
  marginBottom: 20,
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const processChecklistTitle: React.CSSProperties = {
  fontSize: 13,
  fontWeight: 900,
  color: "#111827",
  textTransform: "uppercase",
  letterSpacing: "0.06em",
};

const processChecklistGrid: React.CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
  gap: 14,
};

const processChecklistItem: React.CSSProperties = {
  display: "flex",
  gap: 9,
  alignItems: "flex-start",
  background: "white",
  border: "1px solid #e5e7eb",
  borderRadius: 10,
  padding: "10px 12px",
  minHeight: 58,
};

const page: React.CSSProperties = {
  padding: "20px 28px 32px",
  maxWidth: 1180,
  margin: "0 auto",
  textAlign: "left",
};

const headerBox: React.CSSProperties = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "flex-start",
  flexWrap: "wrap",
  gap: 16,
  marginBottom: 20,
  paddingBottom: 20,
  borderBottom: "2px solid #e5e7eb",
};

const tenantTag: React.CSSProperties = {
  fontFamily: "monospace",
  fontSize: 12,
  background: "#f3f4f6",
  border: "1px solid #e5e7eb",
  borderRadius: 4,
  padding: "2px 8px",
  color: "#374151",
};

const infoGrid: React.CSSProperties = {
  display: "grid",
  gridTemplateColumns: "1fr 1fr",
  gap: 16,
  marginBottom: 20,
};

const sectionBox: React.CSSProperties = {
  background: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: 12,
  padding: "16px 20px",
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const sectionTitle: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 800,
  color: "#374151",
  textTransform: "uppercase",
  letterSpacing: "0.06em",
  marginBottom: 12,
};

const actionsPanel: React.CSSProperties = {
  background: "#f8fafc",
  border: "1px solid #e2e8f0",
  borderRadius: 10,
  padding: "16px 20px",
  marginBottom: 20,
};

const actionsPanelTitle: React.CSSProperties = {
  fontSize: 12,
  fontWeight: 800,
  color: "#374151",
  textTransform: "uppercase",
  letterSpacing: "0.06em",
  marginBottom: 14,
};

const actionsGrid: React.CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(3, 1fr)",
  gap: 12,
};

const stepperBox: React.CSSProperties = {
  display: "flex",
  alignItems: "flex-start",
  overflowX: "auto",
  padding: "10px 0 16px",
  marginBottom: 20,
  borderBottom: "1px solid #f3f4f6",
};

const actionGroupBox: React.CSSProperties = {
  background: "white",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  padding: "12px 14px",
  display: "flex",
  flexDirection: "column",
  gap: 8,
};

const actionGroupLabelStyle: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 700,
  color: "#374151",
  marginBottom: 2,
};

const btn: React.CSSProperties = {
  fontSize: 12,
  padding: "5px 10px",
  borderRadius: 5,
  border: "1px solid #e5e7eb",
  background: "white",
  cursor: "pointer",
};

const btnPrimary: React.CSSProperties = {
  fontSize: 12,
  padding: "5px 12px",
  borderRadius: 5,
  border: "1px solid #16a34a",
  background: "#dcfce7",
  color: "#166534",
  cursor: "pointer",
  fontWeight: 600,
};

const btnDisabled: React.CSSProperties = {
  fontSize: 12,
  padding: "5px 10px",
  borderRadius: 5,
  border: "1px solid #e5e7eb",
  background: "#f9fafb",
  color: "#d1d5db",
  cursor: "not-allowed",
};

const inputStyle: React.CSSProperties = {
  fontSize: 12,
  padding: "4px 8px",
  border: "1px solid #e5e7eb",
  borderRadius: 4,
  width: "100%",
};

const alignedBadge: React.CSSProperties = {
  display: "inline-block",
  fontSize: 12,
  fontWeight: 600,
  color: "#166534",
  background: "#dcfce7",
  border: "1px solid #86efac",
  borderRadius: 5,
  padding: "3px 10px",
};

const resetLinkBox: React.CSSProperties = {
  display: "flex",
  flexDirection: "column",
  gap: 6,
  background: "#f8fafc",
  border: "1px solid #e2e8f0",
  borderRadius: 8,
  padding: "10px 12px",
};

const resetLinkCode: React.CSSProperties = {
  display: "block",
  fontSize: 11,
  color: "#111827",
  background: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: 6,
  padding: "8px 10px",
  wordBreak: "break-all",
  whiteSpace: "normal",
};

const btnCopied: React.CSSProperties = {
  ...btn,
  background: "#dcfce7",
  borderColor: "#86efac",
  color: "#166534",
  transform: "translateY(-1px) scale(1.02)",
  boxShadow: "0 6px 14px rgba(22, 101, 52, 0.16)",
  transition: "all 160ms ease",
};

const feedbackOk: React.CSSProperties = {
  marginBottom: 14,
  padding: "8px 14px",
  background: "#f0fdf4",
  border: "1px solid #bbf7d0",
  borderRadius: 6,
  fontSize: 13,
  color: "#166534",
};

const feedbackErr: React.CSSProperties = {
  marginBottom: 14,
  padding: "8px 14px",
  background: "#fef2f2",
  border: "1px solid #fecaca",
  borderRadius: 6,
  fontSize: 13,
  color: "#991b1b",
};

const errorBox: React.CSSProperties = {
  marginTop: 24,
  padding: "10px 14px",
  background: "#fef2f2",
  border: "1px solid #fecaca",
  borderRadius: 8,
  color: "#991b1b",
  fontSize: 13,
};
