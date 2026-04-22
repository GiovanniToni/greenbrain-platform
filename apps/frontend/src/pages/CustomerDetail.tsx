import { useCallback, useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import {
  listCustomers,
  assignRelease,
  prepareDelivery,
  markDeliverySent,
  confirmCustomerSlot,
  updateCustomerOnboardingStatus,
  activateCustomerSubscription,
  type CustomerOpsItem,
} from "@/lib/customerOpsApi";
import { planDisplayName, planDisplayPrice } from "@/lib/planConfig";

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

const LATEST_RELEASE = "27684520.2023.2279060";

const NEXT_ONBOARDING_STATUS: Record<string, string> = {
  slot_requested:          "slot_confirmed",
  slot_confirmed:          "setup_in_progress",
  setup_in_progress:       "data_validation_pending",
  data_validation_pending: "data_validated",
};

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

  const load = useCallback(() => {
    if (!customerId) return;
    setLoading(true);
    listCustomers(200)
      .then(({ items }) => {
        const found = items.find((x) => x.customer_id === customerId) ?? null;
        setItem(found);
        if (!found) setError("Cliente non trovato.");
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Errore caricamento"))
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
  const canConfirmSlot = item.onboarding_status === "slot_requested" && slotScheduled.length > 0;
  const canActivateSub = item.onboarding_status === "data_validated" && item.payment_method_saved === true;
  const releaseAligned = item.assigned_release_version === LATEST_RELEASE
    && item.installed_release_version === LATEST_RELEASE;

  return (
    <div style={page}>
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
        </div>
      </div>

      {/* ── action feedback ── */}
      {actionMsg && (
        <div style={actionMsg.type === "ok" ? feedbackOk : feedbackErr}>
          {actionMsg.type === "ok" ? "✓ " : "✗ "}{actionMsg.text}
        </div>
      )}

      {/* ── info grid (2 col) ── */}
      <div style={infoGrid}>

        {/* Left */}
        <div style={{ display: "flex", flexDirection: "column" as const, gap: 12 }}>
          <Section title="Contatti">
            <Row label="Referente" value={item.contact_name} />
            <Row label="Email" value={item.contact_email} />
            <Row label="Telefono" value={item.contact_phone} />
            <Row label="Customer ID" value={<code style={{ fontSize: 11 }}>{item.customer_id}</code>} />
            <Row label="Creato il" value={fmtDt(item.created_at)} />
            <Row label="Aggiornato il" value={fmtDt(item.updated_at, "datetime")} />
          </Section>

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
        </div>

        {/* Right */}
        <div style={{ display: "flex", flexDirection: "column" as const, gap: 12 }}>
          <Section title="Pagamento e abbonamento">
            <Row label="Piano" value={planName !== "—" ? `${planName}${planPrice ? ` — ${planPrice}` : ""}` : null} />
            <Row label="Stato abbonamento" value={badge(item.subscription_status)} />
            <Row
              label="Metodo di pagamento"
              value={
                item.payment_method_saved
                  ? `${item.payment_method_brand?.toUpperCase() || "Carta"} ••••${item.payment_method_last4 || ""}`
                  : "Non salvato"
              }
            />
          </Section>

          <Section title="Onboarding">
            <Row label="Stato" value={badge(item.onboarding_status)} />
            <Row label="Install status" value={badge(item.install_status)} />
            <Row label="DB integration" value={badge(item.db_integration_status)} />
            <Row label="Dati validati il" value={fmtDt(item.data_validated_at)} />
          </Section>

          <Section title="Release e delivery">
            <Row label="Release assegnata" value={item.assigned_release_version || item.delivery_assigned_release_version} />
            <Row label="Release installata" value={item.installed_release_version} />
            <Row label="Release target" value={<strong>{LATEST_RELEASE}</strong>} />
            <Row label="Bundle generato il" value={fmtDt(item.bundle_generated_at, "datetime")} />
            <Row label="Bundle inviato il" value={fmtDt(item.bundle_sent_at, "datetime")} />
            <Row label="Bundle path" value={item.bundle_local_path ? <code style={{ fontSize: 10, wordBreak: "break-all" as const }}>{item.bundle_local_path}</code> : null} />
            <Row label="Go-live il" value={fmtDt(item.go_live_at, "datetime")} />
            <Row label="Delivery stato" value={badge(item.delivery_install_status)} />
          </Section>
        </div>
      </div>

      {/* ── operator actions ── */}
      <div style={actionsPanel}>
        <div style={actionsPanelTitle}>Azioni operative</div>
        <div style={actionsGrid}>

          {/* Slot */}
          <ActionGroup emoji="📅" title="Slot setup">
            {item.setup_slot_scheduled_for ? (
              <span style={{ fontSize: 12, color: "#16a34a" }}>✓ Confermato — {fmtDt(item.setup_slot_scheduled_for, "datetime")}</span>
            ) : item.onboarding_status === "slot_requested" ? (
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
            ) : item.setup_slot_scheduled_for ? (
              <span style={{ fontSize: 12, color: "#16a34a" }}>
                ✓ Confermato — {fmtDt(item.setup_slot_scheduled_for, "datetime")}
              </span>
            ) : item.setup_slot_preferred_date ? (
              <span style={{ fontSize: 11, color: "#6b7280" }}>
                Slot richiesto dal cliente, in attesa di conferma operatore
              </span>
            ) : (
              <span style={{ fontSize: 11, color: "#9ca3af" }}>Slot non ancora richiesto</span>
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

              return <span style={{ fontSize: 11, color: "#16a34a" }}>✓ Completato</span>;
            })()}
          </ActionGroup>

          {/* Subscription */}
          <ActionGroup emoji="💳" title="Abbonamento">
            {item.subscription_status === "active" ? (
              <span style={{ fontSize: 12, color: "#16a34a" }}>✓ Abbonamento attivo</span>
            ) : (
              <>
                <button
                  onClick={() => run(async () => {
                    await activateCustomerSubscription(item.customer_id);
                    return `Abbonamento attivato per ${item.company_name}`;
                  })}
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
              </>
            )}
          </ActionGroup>

          {/* Delivery */}
          <ActionGroup emoji="📦" title="Delivery">
            <div style={{ fontSize: 11, color: "#6b7280", marginBottom: 4, lineHeight: 1.6 }}>
              Target: <strong>{LATEST_RELEASE}</strong>
              {" · "}Assegnata: <strong>{item.assigned_release_version || "—"}</strong>
              {" · "}Installata: <strong>{item.installed_release_version || "—"}</strong>
            </div>
            {releaseAligned ? (
              <span style={alignedBadge}>✓ Sistema aggiornato</span>
            ) : (
              <button
                onClick={() => run(async () => {
                  const res = await assignRelease(item.customer_id, LATEST_RELEASE);
                  await prepareDelivery(item.customer_id);
                  return `Release ${res.assigned_release_version} assegnata, delivery preparata`;
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
  gridTemplateColumns: "1fr 1fr",
  gap: 12,
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
