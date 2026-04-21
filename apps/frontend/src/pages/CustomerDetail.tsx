import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { listCustomers, type CustomerOpsItem } from "@/lib/customerOpsApi";
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

export default function CustomerDetail() {
  const { customerId } = useParams<{ customerId: string }>();
  const [item, setItem] = useState<CustomerOpsItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
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
        <div style={{ marginTop: 24, padding: "10px 14px", background: "#fef2f2", border: "1px solid #fecaca", borderRadius: 8, color: "#991b1b", fontSize: 13 }}>
          {error || "Cliente non trovato."}
        </div>
      </div>
    );
  }

  const planName  = planDisplayName(item.subscription_plan);
  const planPrice = planDisplayPrice(item.subscription_plan);

  return (
    <div style={page}>
      <BackLink />

      {/* ── company header ── */}
      <div style={header}>
        <div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 800 }}>{item.company_name}</h1>
          {item.tenant_code && (
            <span style={{ display: "inline-block", marginTop: 6, fontFamily: "monospace", fontSize: 12, background: "#f3f4f6", border: "1px solid #e5e7eb", borderRadius: 4, padding: "2px 8px", color: "#374151" }}>
              {item.tenant_code}
            </span>
          )}
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-start" }}>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 10, color: "#9ca3af", fontWeight: 700, textTransform: "uppercase", marginBottom: 4 }}>Onboarding</div>
            {badge(item.onboarding_status)}
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 10, color: "#9ca3af", fontWeight: 700, textTransform: "uppercase", marginBottom: 4 }}>Abbonamento</div>
            {badge(item.subscription_status)}
          </div>
        </div>
      </div>

      {/* ── sections ── */}

      <Section title="Contatti">
        <Row label="Referente" value={item.contact_name} />
        <Row label="Email" value={item.contact_email} />
        <Row label="Telefono" value={item.contact_phone} />
        <Row label="Customer ID" value={<span style={{ fontFamily: "monospace", fontSize: 11 }}>{item.customer_id}</span>} />
      </Section>

      <Section title="Onboarding">
        <Row label="Stato onboarding" value={badge(item.onboarding_status)} />
        <Row label="Install status" value={badge(item.install_status)} />
        <Row label="DB integration" value={badge(item.db_integration_status)} />
        <Row label="Dati validati il" value={fmtDt(item.data_validated_at)} />
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

      <Section title="Pagamento e abbonamento">
        <Row
          label="Metodo di pagamento"
          value={
            item.payment_method_saved
              ? `${item.payment_method_brand?.toUpperCase() || "Carta"} ••••${item.payment_method_last4 || ""}`
              : "Non salvato"
          }
        />
        <Row label="Piano" value={planName !== "—" ? `${planName}${planPrice ? ` — ${planPrice}` : ""}` : null} />
        <Row label="Stato abbonamento" value={badge(item.subscription_status)} />
      </Section>

      <Section title="Release e bundle">
        <Row label="Release assegnata" value={item.assigned_release_version || item.delivery_assigned_release_version} />
        <Row label="Release installata" value={item.installed_release_version} />
        <Row label="Bundle generato il" value={fmtDt(item.bundle_generated_at, "datetime")} />
        <Row label="Bundle inviato il" value={fmtDt(item.bundle_sent_at, "datetime")} />
        <Row label="Bundle path" value={item.bundle_local_path ? <span style={{ fontFamily: "monospace", fontSize: 11, wordBreak: "break-all" }}>{item.bundle_local_path}</span> : null} />
      </Section>

      <Section title="Delivery">
        <Row label="Install status delivery" value={badge(item.delivery_install_status)} />
        <Row label="Onboarding status delivery" value={badge(item.delivery_onboarding_status)} />
        <Row label="Go-live il" value={fmtDt(item.go_live_at, "datetime")} />
        <Row label="Delivery aggiornata il" value={fmtDt(item.delivery_updated_at, "datetime")} />
      </Section>

      <div style={{ marginTop: 24 }}>
        <Link to="/customers" style={{ fontSize: 13, color: "#6b7280" }}>
          ← Torna alla lista clienti
        </Link>
      </div>
    </div>
  );
}

function BackLink() {
  return (
    <div style={{ marginBottom: 16 }}>
      <Link to="/customers" style={{ fontSize: 13, color: "#6b7280", textDecoration: "none" }}>
        ← Clienti
      </Link>
    </div>
  );
}

// ── styles ────────────────────────────────────────────────────────────────────

const page: React.CSSProperties = {
  padding: 24,
  maxWidth: 860,
  textAlign: "left",
};

const header: React.CSSProperties = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "flex-start",
  flexWrap: "wrap",
  gap: 16,
  marginBottom: 24,
  paddingBottom: 16,
  borderBottom: "1px solid #e5e7eb",
};

const sectionBox: React.CSSProperties = {
  background: "#f9fafb",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  padding: "14px 18px",
  marginBottom: 14,
};

const sectionTitle: React.CSSProperties = {
  fontSize: 11,
  fontWeight: 800,
  color: "#374151",
  textTransform: "uppercase",
  letterSpacing: "0.06em",
  marginBottom: 12,
};
