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
  DELIVERY_STATUS_LABELS,
  type CustomerOpsItem,
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
  const releaseAligned = item.assigned_release_version === LATEST_RELEASE;
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

  const effectiveInstalledRelease =
    item.installed_release_version ||
    (item.delivery_install_status === "installed"
      ? (item.delivery_assigned_release_version || null)
      : null);

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

      {/* ── onboarding stepper ── */}
      <OnboardingStepper item={item} />

      {/* ── action feedback ── */}
      {actionMsg && (
        <div style={actionMsg.type === "ok" ? feedbackOk : feedbackErr}>
          {actionMsg.type === "ok" ? "✓ " : "✗ "}{actionMsg.text}
        </div>
      )}

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
            {item.subscription_current_period_end && (
              <Row label="Attivo fino al" value={fmtDt(item.subscription_current_period_end, "datetime")} />
            )}
            {item.subscription_current_period_end && (
              <Row label="Prossimo addebito" value={fmtDt(item.subscription_current_period_end, "datetime")} />
            )}
            {item.subscription_cancel_at_period_end !== null && item.subscription_cancel_at_period_end !== undefined && (
              <Row label="Rinnovo automatico" value={item.subscription_cancel_at_period_end ? "Disattivato" : "Attivo"} />
            )}
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
          </Section>

          <Section title="Onboarding e validazione">
            <Row label="Stato" value={badge(item.onboarding_status)} />
            <Row label="Install status" value={badge(effectiveInstallStatus)} />
            <Row label="Delivery install status" value={badge(item.delivery_install_status)} />
            <Row label="DB integration" value={badge(effectiveDbIntegrationStatus)} />
            <Row label="Dati validati il" value={fmtDt(item.data_validated_at)} />
          </Section>

          <Section title="Release e delivery">
            <Row label="Release assegnata" value={item.assigned_release_version || item.delivery_assigned_release_version} />
            <Row label="Release delivery" value={item.delivery_assigned_release_version} />
            <Row label="Release installata" value={effectiveInstalledRelease} />
            <Row label="Ultima scaricata" value={item.last_downloaded_release_version} />
            <Row label="Scaricata il" value={fmtDt(item.last_downloaded_at, "datetime")} />
            <Row label="Release target" value={<strong>{LATEST_RELEASE}</strong>} />
            <Row label="Bundle generato il" value={fmtDt(item.bundle_generated_at, "datetime")} />
            <Row label="Bundle inviato il" value={fmtDt(item.bundle_sent_at, "datetime")} />
            <Row label="Bundle path" value={item.bundle_local_path ? <code style={{ fontSize: 10, wordBreak: "break-all" as const }}>{item.bundle_local_path}</code> : null} />
            <Row label="Go-live il" value={fmtDt(item.go_live_at, "datetime")} />
            <Row label="Delivery stato" value={item.delivery_status ? badge(DELIVERY_STATUS_LABELS[item.delivery_status] ?? item.delivery_status) : badge(item.delivery_install_status)} />
          </Section>
        </div>
      </div>

      {/* ── operator process checklist ── */}
      <div style={{ background: "#f8fafc", border: "1px solid #e2e8f0", borderRadius: 10, padding: "14px 20px", marginBottom: 20 }}>
        <div style={{ fontSize: 11, fontWeight: 800, color: "#374151", textTransform: "uppercase" as const, letterSpacing: "0.06em", marginBottom: 10 }}>
          Checklist processo
        </div>
        <div style={{ display: "flex", flexWrap: "wrap" as const, gap: "8px 24px" }}>
          {([
            { done: Boolean(item.payment_method_saved),                                               label: "Pagamento salvato" },
            { done: Boolean(item.setup_slot_requested_at),                                            label: "Slot richiesto" },
            { done: Boolean(item.setup_slot_confirmed_at || item.setup_slot_scheduled_for),           label: "Slot confermato" },
            { done: Boolean(item.last_downloaded_at),                                                 label: "Bundle scaricato" },
            { done: Boolean(item.data_validated_at),                                                  label: "Dati validati" },
            { done: (item.subscription_status || "").toLowerCase() === "active",                      label: "Abbonamento attivo" },
          ] as { done: boolean; label: string }[]).map(({ done, label }, i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 12 }}>
              <span style={{ color: done ? "#16a34a" : "#d1d5db", fontWeight: 800, fontSize: 13 }}>
                {done ? "✓" : "○"}
              </span>
              <span style={{ color: done ? "#166534" : "#9ca3af", fontWeight: done ? 600 : 400 }}>
                {label}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* ── operator actions ── */}
      <div style={actionsPanel}>
        <div style={actionsPanelTitle}>Azioni operative</div>
        <div style={actionsGrid}>

          {/* Slot */}
          <ActionGroup emoji="📅" title="Slot setup">
            {slotAlreadyConfirmed ? (
              <span style={{ fontSize: 12, color: "#16a34a" }}>✓ Confermato — {fmtDt(item.setup_slot_scheduled_for, "datetime")}</span>
            ) : item.onboarding_status === "slot_confirmed" ? (
              <span style={{ fontSize: 11, color: "#6b7280" }}>Slot confermato, schedulazione in corso</span>
            ) : canShowConfirmSlot ? (
              <>
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
              </>
            ) : item.setup_slot_preferred_date ? (
              <span style={{ fontSize: 11, color: "#6b7280" }}>Preferenza: {item.setup_slot_preferred_date}</span>
            ) : (
              <span style={{ fontSize: 11, color: "#9ca3af" }}>—</span>
            )}
          </ActionGroup>

          {/* Onboarding */}
          <ActionGroup emoji="🔄" title="Avanzamento onboarding">
            <div style={{ fontSize: 11, color: "#6b7280", marginBottom: 4 }}>
              Stato attuale: {badge(item.onboarding_status)}
            </div>
            {(() => {
              const waitingCustomerStatuses = ["draft", "signup_started", "checkout_started"];

              if (waitingCustomerStatuses.includes(item.onboarding_status || "")) {
                return (
                  <span style={{ fontSize: 11, color: "#9ca3af" }}>
                    In attesa azione cliente
                  </span>
                );
              }

              if (nextStatus) {
                return (
                  <button
                    onClick={() => run(async () => {
                      await updateCustomerOnboardingStatus(item.customer_id, nextStatus);
                      return `Stato aggiornato: ${nextStatus}`;
                    })}
                    disabled={busy}
                    style={busy ? btnDisabled : btn}
                  >
                    → {nextStatus}
                  </button>
                );
              }

              if (item.onboarding_status === "data_validated") {
                return <span style={{ fontSize: 11, color: "#16a34a" }}>✓ Completato</span>;
              }
              return <span style={{ fontSize: 11, color: "#9ca3af" }}>Stato: {item.onboarding_status || "—"}</span>;
            })()}
          </ActionGroup>

          {/* Subscription */}
          <ActionGroup emoji="💳" title="Abbonamento">
            {item.subscription_status === "active" ? (
              <span style={{ fontSize: 12, color: "#16a34a" }}>✓ Abbonamento attivo</span>
            ) : (
              <>
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
                {!canActivateSub && (
                  <span style={{ fontSize: 10, color: "#9ca3af" }}>
                    Richiede validazione dati e metodo di pagamento
                  </span>
                )}
                <button
                  onClick={() => { setForceModal(true); setForceConfirmed(false); setForceText(""); }}
                  disabled={busy || item.subscription_status === "active"}
                  style={{ ...btn, fontSize: 11, color: "#b45309", borderColor: "#fcd34d", marginTop: 2 }}
                >
                  Attiva abbonamento (override)
                </button>
              </>
            )}
          </ActionGroup>

          {/* Delivery */}
          <ActionGroup emoji="📦" title="Delivery">
            <div style={{ display: "grid", gridTemplateColumns: "auto 1fr", columnGap: 10, rowGap: 3, fontSize: 11, marginBottom: 6 }}>
              <span style={{ color: "#9ca3af" }}>Target</span>
              <strong style={{ color: "#111827" }}>{LATEST_RELEASE}</strong>
              <span style={{ color: "#9ca3af" }}>Assegnata</span>
              <strong style={{ color: "#111827" }}>{item.assigned_release_version || "—"}</strong>
              <span style={{ color: "#9ca3af" }}>Installata</span>
              <strong style={{ color: "#111827" }}>{item.installed_release_version || "—"}</strong>
              {item.delivery_status && (
                <>
                  <span style={{ color: "#9ca3af" }}>Stato</span>
                  <span style={{
                    fontWeight: 700,
                    color: item.delivery_status === "installed" ? "#166534"
                         : item.delivery_status === "failed" ? "#991b1b"
                         : item.delivery_status === "sent" ? "#1e40af"
                         : "#374151",
                  }}>
                    {DELIVERY_STATUS_LABELS[item.delivery_status] ?? item.delivery_status}
                  </span>
                </>
              )}
            </div>
            {releaseAligned ? (
              <span style={alignedBadge}>✓ Sistema aggiornato</span>
            ) : (
              <button
                onClick={() => run(async () => {
                  const res = await sendRelease(item.customer_id, LATEST_RELEASE);
                  const label = DELIVERY_STATUS_LABELS[res.delivery_status] ?? res.delivery_status;
                  return `Release ${res.assigned_release_version} inviata — delivery: ${label}`;
                })}
                disabled={busy}
                style={busy ? btnDisabled : btnPrimary}
              >
                Invia release {LATEST_RELEASE}
              </button>
            )}
            <button
              onClick={() => run(async () => {
                const res = await markDeliverySent(item.customer_id);
                return `Bundle marcato come inviato (${res.bundle_sent_at || "—"})`;
              })}
              disabled={busy || !item.bundle_generated_at}
              style={{ ...(busy || !item.bundle_generated_at ? btnDisabled : btn), marginTop: 6 }}
            >
              Segna come inviato
            </button>
          </ActionGroup>

          {/* Disdetta */}
          <ActionGroup emoji="🚫" title="Gestione disdetta">
            {item.cancellation_requested ? (
              <>
                <div style={{ background: "#fef3c7", border: "1px solid #fcd34d", borderRadius: 5, padding: "6px 10px", fontSize: 11 }}>
                  <div style={{ fontWeight: 700, color: "#92400e" }}>Disdetta richiesta</div>
                  <div style={{ color: "#b45309", marginTop: 2 }}>{fmtDt(item.cancellation_requested_at, "datetime") || "—"}</div>
                </div>
                <span style={{ fontSize: 10, color: "#9ca3af" }}>In attesa gestione amministrativa</span>
                <button disabled style={btnDisabled}>Richiedi disdetta</button>
              </>
            ) : (() => {
              const canCancel = ["active", "trialing", "past_due", "incomplete"].includes(
                (item.subscription_status || "").toLowerCase(),
              );
              return (
                <>
                  <button
                    onClick={() => run(async () => {
                      await requestCustomerCancellation(item.customer_id);
                      return "Richiesta registrata — in attesa gestione amministrativa";
                    })}
                    disabled={busy || !canCancel}
                    style={canCancel && !busy ? btn : btnDisabled}
                  >
                    Richiedi disdetta
                  </button>
                  {!canCancel && (
                    <span style={{ fontSize: 10, color: "#9ca3af" }}>
                      Solo per abbonamenti attivi / in scadenza
                    </span>
                  )}
                </>
              );
            })()}
          </ActionGroup>

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

const page: React.CSSProperties = {
  padding: 24,
  maxWidth: 920,
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
  gap: 12,
  marginBottom: 20,
};

const sectionBox: React.CSSProperties = {
  background: "#f9fafb",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  padding: "14px 18px",
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
