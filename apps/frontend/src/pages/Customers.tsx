import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { LATEST_RELEASE, customerHealth } from "@/lib/opsConfig";
import {
  assignRelease,
  confirmCustomerSlot,
  activateCustomerSubscription,
  listCustomers,
  markDeliverySent,
  prepareDelivery,
  sendRelease,
  updateCustomerOnboardingStatus,
  DELIVERY_STATUS_LABELS,
  type CustomerOpsItem,
} from "@/lib/customerOpsApi";

const STATUS_COLORS: Record<string, { bg: string; color: string }> = {
  active:                   { bg: "#dcfce7", color: "#166534" },
  data_validated:           { bg: "#dcfce7", color: "#166534" },
  installed:                { bg: "#dcfce7", color: "#166534" },
  slot_requested:           { bg: "#fef9c3", color: "#854d0e" },
  data_validation_pending:  { bg: "#fef9c3", color: "#854d0e" },
  checkout_started:         { bg: "#fef9c3", color: "#854d0e" },
  slot_confirmed:           { bg: "#ede9fe", color: "#5b21b6" },
  setup_in_progress:        { bg: "#ede9fe", color: "#5b21b6" },
  failed:                   { bg: "#fee2e2", color: "#991b1b" },
  error:                    { bg: "#fee2e2", color: "#991b1b" },
  past_due:                 { bg: "#fee2e2", color: "#991b1b" },
  incomplete:               { bg: "#fee2e2", color: "#991b1b" },
};

function statusBadge(status: string | null | undefined) {
  const s = (status || "—").toLowerCase();
  const c = STATUS_COLORS[s] ?? { bg: "#f3f4f6", color: "#6b7280" };
  return (
    <span style={{
      background: c.bg, color: c.color,
      borderRadius: 4, padding: "2px 7px",
      fontSize: 11, fontWeight: 600,
      display: "inline-block", whiteSpace: "nowrap",
    }}>
      {status || "—"}
    </span>
  );
}

const NEXT_ONBOARDING_STATUS: Record<string, string> = {
  slot_requested:          "slot_confirmed",
  slot_confirmed:          "setup_in_progress",
  setup_in_progress:       "data_validation_pending",
  data_validation_pending: "data_validated",
};

const PIPELINE_STEPS: { key: string; short: string }[] = [
  { key: "slot_requested",          short: "Slot" },
  { key: "slot_confirmed",          short: "Conf." },
  { key: "setup_in_progress",       short: "Setup" },
  { key: "data_validation_pending", short: "Val." },
  { key: "data_validated",          short: "Validato" },
];

function PipelineBar({ item }: { item: CustomerOpsItem }) {
  const isActive = (item.subscription_status || "").toLowerCase() === "active";
  const currentIdx = isActive
    ? PIPELINE_STEPS.length
    : PIPELINE_STEPS.findIndex((s) => s.key === item.onboarding_status);

  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 2, marginTop: 5 }}>
      {PIPELINE_STEPS.map((step, i) => {
        const done = isActive || currentIdx > i;
        const current = !isActive && currentIdx === i;
        return (
          <span
            key={step.key}
            title={step.key}
            style={{
              fontSize: 9, fontWeight: current ? 800 : 600,
              padding: "1px 5px", borderRadius: 3, whiteSpace: "nowrap" as const,
              background: done ? "#dcfce7" : current ? "#ede9fe" : "#f3f4f6",
              color: done ? "#166534" : current ? "#5b21b6" : "#9ca3af",
              border: current ? "1px solid #a78bfa" : "1px solid transparent",
            }}
          >
            {done ? "✓" : ""}{step.short}
          </span>
        );
      })}
      {isActive && (
        <span style={{ fontSize: 9, fontWeight: 800, padding: "1px 5px", borderRadius: 3, background: "#dcfce7", color: "#166534", border: "1px solid #86efac", whiteSpace: "nowrap" as const }}>
          ✓ Attivo
        </span>
      )}
    </div>
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

const DELIVERY_BADGE_COLORS: Record<string, { bg: string; color: string }> = {
  pending:   { bg: "#fef9c3", color: "#854d0e" },
  prepared:  { bg: "#ede9fe", color: "#5b21b6" },
  sent:      { bg: "#dbeafe", color: "#1e40af" },
  installed: { bg: "#dcfce7", color: "#166534" },
  failed:    { bg: "#fee2e2", color: "#991b1b" },
};

function deliveryStatusBadge(ds: string | null | undefined) {
  if (!ds) return null;
  const label = DELIVERY_STATUS_LABELS[ds] ?? ds;
  const c = DELIVERY_BADGE_COLORS[ds.toLowerCase()] ?? { bg: "#f3f4f6", color: "#6b7280" };
  return (
    <span style={{
      background: c.bg, color: c.color,
      fontSize: 9, fontWeight: 700,
      padding: "1px 5px", borderRadius: 3,
      display: "inline-block", whiteSpace: "nowrap" as const,
    }}>
      {label}
    </span>
  );
}

export default function Customers() {
  const [items, setItems] = useState<CustomerOpsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [releaseByCustomer, setReleaseByCustomer] = useState<Record<string, string>>({});
  const [busyCustomerId, setBusyCustomerId] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [slotScheduledByCustomer, setSlotScheduledByCustomer] = useState<Record<string, string>>({});
  const [search, setSearch] = useState("");
  const [quickFilter, setQuickFilter] = useState("tutti");

  const defaultRelease = LATEST_RELEASE;

  async function load() {
    try {
      setLoading(true);
      setError(null);
      const data = await listCustomers(100);
      const nextItems = data.items || [];
      setItems(nextItems);

      setReleaseByCustomer((prev) => {
        const next = { ...prev };
        for (const item of nextItems) {
          if (!next[item.customer_id]) {
            next[item.customer_id] =
              item.assigned_release_version ||
              item.delivery_assigned_release_version ||
              defaultRelease;
          }
        }
        return next;
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore caricamento clienti");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  const sortedItems = useMemo(
    () =>
      [...items].sort((a, b) =>
        (a.company_name || "").localeCompare(b.company_name || "", "it"),
      ),
    [items],
  );

  const stats = useMemo(() => ({
    total: items.length,
    paymentSaved: items.filter((x) => x.payment_method_saved).length,
    noPayment: items.filter((x) => !x.payment_method_saved).length,
    slotRequested: items.filter((x) =>
      x.onboarding_status === "slot_requested" || x.onboarding_status === "slot_confirmed"
    ).length,
    dataValidationPending: items.filter((x) => x.onboarding_status === "data_validation_pending").length,
    active: items.filter((x) => x.subscription_status === "active").length,
    deliveryPending: items.filter((x) =>
      Boolean(x.assigned_release_version) &&
      (!x.delivery_status || x.delivery_status === "pending" || x.delivery_status === "prepared")
    ).length,
  }), [items]);

  const filteredItems = useMemo(() => {
    let result = sortedItems;

    if (search.trim()) {
      const q = search.trim().toLowerCase();
      result = result.filter((item) =>
        (item.company_name || "").toLowerCase().includes(q) ||
        (item.tenant_code || "").toLowerCase().includes(q) ||
        (item.contact_email || "").toLowerCase().includes(q),
      );
    }

    switch (quickFilter) {
      case "awaiting_payment":
        result = result.filter((x) => !x.payment_method_saved);
        break;
      case "slot_requested":
        result = result.filter((x) => x.onboarding_status === "slot_requested");
        break;
      case "data_validation_pending":
        result = result.filter((x) => x.onboarding_status === "data_validation_pending");
        break;
      case "active":
        result = result.filter((x) => x.subscription_status === "active");
        break;
      default:
        break;
    }

    return result;
  }, [sortedItems, search, quickFilter]);

  async function handleAssignRelease(customerId: string) {
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      const version = releaseByCustomer[customerId] || defaultRelease;
      const result = await assignRelease(customerId, version);
      setActionMessage(
        `Release assegnata: ${result.assigned_release_version} per customer ${result.customer_id}`,
      );
      await load();
    } catch (err) {
      setActionMessage(
        err instanceof Error ? err.message : "Errore durante assign release",
      );
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handlePrepareDelivery(customerId: string) {
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      const result = await prepareDelivery(customerId);
      setActionMessage(
        `Delivery plan pronto per ${result.company_name || customerId} (${result.assigned_release_version || "-"})`,
      );
      await load();
    } catch (err) {
      setActionMessage(
        err instanceof Error ? err.message : "Errore durante prepare delivery",
      );
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handleMarkSent(customerId: string) {
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      const result = await markDeliverySent(customerId);
      setActionMessage(
        `Bundle marcato come inviato per ${result.customer_id} alle ${result.bundle_sent_at || "-"}`,
      );
      await load();
    } catch (err) {
      setActionMessage(
        err instanceof Error ? err.message : "Errore durante mark sent",
      );
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handleSendRelease(customerId: string) {
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      const r = await sendRelease(customerId, LATEST_RELEASE);
      const label = DELIVERY_STATUS_LABELS[r.delivery_status] ?? r.delivery_status;
      setActionMessage(`Release ${r.assigned_release_version} inviata — delivery: ${label}`);
      await load();
    } catch (err) {
      setActionMessage(err instanceof Error ? err.message : "Errore invio release");
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handleConfirmSlot(customerId: string) {
    const scheduled = slotScheduledByCustomer[customerId];
    if (!scheduled) return;
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      await confirmCustomerSlot(customerId, scheduled);
      setActionMessage(`Slot confermato per ${customerId}: ${scheduled}`);
      await load();
    } catch (err) {
      setActionMessage(err instanceof Error ? err.message : "Errore conferma slot");
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handleUpdateStatus(customerId: string, newStatus: string) {
    if (!newStatus) return;
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      await updateCustomerOnboardingStatus(customerId, newStatus);
      setActionMessage(`Stato aggiornato: ${newStatus}`);
      await load();
    } catch (err) {
      setActionMessage(err instanceof Error ? err.message : "Errore aggiornamento stato");
    } finally {
      setBusyCustomerId(null);
    }
  }

  async function handleActivateSub(customerId: string) {
    try {
      setBusyCustomerId(customerId);
      setActionMessage(null);
      await activateCustomerSubscription(customerId);
      setActionMessage(`Abbonamento attivato per ${customerId}`);
      await load();
    } catch (err) {
      setActionMessage(err instanceof Error ? err.message : "Errore attivazione abbonamento");
    } finally {
      setBusyCustomerId(null);
    }
  }

  const busy = (id: string) => busyCustomerId === id;

  return (
    <div style={page}>

      {/* header */}
      <div style={headerBox}>
        <div>
          <h1 style={{ margin: 0, fontSize: 26, fontWeight: 850 }}>Gestione clienti</h1>
          <div style={{ fontSize: 13, color: "#6b7280", marginTop: 4 }}>
            Monitoraggio operativo clienti, onboarding, pagamenti, slot e release.
          </div>
        </div>
        <button onClick={load} disabled={loading} style={btn}>
          {loading ? "Caricamento..." : "↺ Ricarica"}
        </button>
      </div>

      {/* summary strip */}
      <div style={summaryGrid}>
        {[
          { label: "Totale",            value: stats.total,                color: "#374151", alert: false },
          { label: "Attivi",            value: stats.active,               color: "#16a34a", alert: false },
          { label: "Pagamento salvato", value: stats.paymentSaved,         color: "#0369a1", alert: false },
          { label: "Senza pagamento",   value: stats.noPayment,            color: "#b91c1c", alert: stats.noPayment > 0 },
          { label: "Slot / conferma",   value: stats.slotRequested,        color: "#d97706", alert: stats.slotRequested > 0 },
          { label: "Val. pendente",     value: stats.dataValidationPending,color: "#7c3aed", alert: stats.dataValidationPending > 0 },
          { label: "Delivery pendente", value: stats.deliveryPending,      color: "#0369a1", alert: stats.deliveryPending > 0 },
        ].map(({ label, value, color, alert }) => (
          <div
            key={label}
            style={{
              ...statBox,
              borderColor: alert && value > 0 ? `${color}60` : undefined,
              background: alert && value > 0 ? `${color}08` : undefined,
            }}
          >
            <div style={{ fontSize: 22, fontWeight: 800, lineHeight: 1, color }}>{value}</div>
            <div style={{ fontSize: 10, color: "#6b7280", marginTop: 3 }}>{label}</div>
          </div>
        ))}
      </div>

      {/* search + quick filters */}
      <div style={toolbarBox}>
        <input
          type="search"
          placeholder="Cerca per azienda, tenant, email..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={searchInput}
        />

        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
        {([
          { key: "tutti", label: "Tutti" },
          { key: "awaiting_payment", label: "In attesa pagamento" },
          { key: "slot_requested", label: "Slot richiesti" },
          { key: "data_validation_pending", label: "Validazione dati" },
          { key: "active", label: "Attivi" },
        ] as const).map((f) => (
          <button
            key={f.key}
            onClick={() => setQuickFilter(f.key)}
            style={{
              padding: "4px 12px", borderRadius: 6, border: "1px solid", cursor: "pointer", fontSize: 13,
              borderColor: quickFilter === f.key ? "#16a34a" : "#e5e7eb",
              background: quickFilter === f.key ? "#dcfce7" : "white",
              color: quickFilter === f.key ? "#166534" : "#374151",
            }}
          >
            {f.label}
          </button>
        ))}
        </div>
      </div>

      {/* error */}
      {error && (
        <div style={{ marginBottom: 12, padding: "8px 12px", background: "#fef2f2", border: "1px solid #fecaca", borderRadius: 6, color: "#991b1b", fontSize: 13 }}>
          <strong>Errore:</strong> {error}
        </div>
      )}

      {/* action feedback */}
      {actionMessage && (
        <div style={{ marginBottom: 12, padding: "8px 12px", background: "#f0fdf4", border: "1px solid #bbf7d0", borderRadius: 6, fontSize: 13, color: "#166534" }}>
          <strong>Esito:</strong> {actionMessage}
        </div>
      )}

      {/* table */}
      <div style={tableCard}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th style={th}>Cliente</th>
              <th style={th}>Onboarding</th>
              <th style={th}>Slot</th>
              <th style={th}>Abbonamento</th>
              <th style={th}>Release / Bundle</th>
              <th style={th}>Azioni</th>
            </tr>
          </thead>
          <tbody>
            {filteredItems.map((item) => (
              <tr key={item.customer_id}>

                {/* Cliente */}
                <td style={td}>
                  <div style={{ fontWeight: 600, fontSize: 14 }}>
                    <Link
                      to={`/customers/${item.customer_id}`}
                      style={{ color: "inherit", textDecoration: "none", borderBottom: "1px solid #d1d5db" }}
                    >
                      {item.company_name}
                    </Link>
                  </div>
                  <div style={{ fontSize: 11, color: "#6b7280", marginTop: 2 }}>{item.tenant_code || "—"}</div>
                  <div style={{ fontSize: 11, color: "#9ca3af" }}>{item.contact_email}</div>
                  {(() => {
                    const h = customerHealth(item);
                    return (
                      <span style={{ display: "inline-block", marginTop: 5, fontSize: 10, fontWeight: 700, background: h.bg, color: h.color, borderRadius: 4, padding: "2px 7px", border: `1px solid ${h.color}30` }}>
                        {h.label}
                      </span>
                    );
                  })()}
                </td>

                {/* Onboarding */}
                <td style={td}>
                  {statusBadge(item.onboarding_status)}
                  <PipelineBar item={item} />
                  {item.data_validated_at && (
                    <div style={{ fontSize: 10, color: "#16a34a", marginTop: 4 }}>
                      ✓ Validato: {fmtDt(item.data_validated_at)}
                    </div>
                  )}
                </td>

                {/* Slot */}
                <td style={td}>
                  {item.setup_slot_scheduled_for ? (
                    <>
                      <div style={{ fontSize: 11, fontWeight: 600 }}>{fmtDt(item.setup_slot_scheduled_for, "datetime")}</div>
                      <div style={{ fontSize: 10, color: "#16a34a" }}>✓ Confermato</div>
                    </>
                  ) : item.setup_slot_preferred_date ? (
                    <>
                      <div style={{ fontSize: 11 }}>{item.setup_slot_preferred_date}</div>
                      <div style={{ fontSize: 10, color: "#6b7280" }}>
                        {item.setup_slot_preferred_time === "morning" ? "Mattina"
                          : item.setup_slot_preferred_time === "afternoon" ? "Pomeriggio"
                          : item.setup_slot_preferred_time || ""}
                      </div>
                      <div style={{ fontSize: 10, color: "#f59e0b" }}>In attesa conferma</div>
                    </>
                  ) : (
                    <span style={{ color: "#9ca3af", fontSize: 11 }}>—</span>
                  )}
                  {item.setup_slot_confirmed_at && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 3 }}>
                      conf. il: {fmtDt(item.setup_slot_confirmed_at)}
                    </div>
                  )}
                  {item.setup_slot_requested_at && !item.setup_slot_scheduled_for && (
                    <div style={{ fontSize: 10, color: "#9ca3af", marginTop: 2 }}>
                      richiesto: {fmtDt(item.setup_slot_requested_at)}
                    </div>
                  )}
                </td>

                {/* Abbonamento */}
                <td style={td}>
                  {statusBadge(item.subscription_status || "—")}
                  {item.subscription_plan && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 3 }}>
                      Piano: {item.subscription_plan}
                    </div>
                  )}
                  {item.payment_method_saved ? (
                    <div style={{ fontSize: 10, color: "#16a34a", marginTop: 4 }}>
                      ✓ {item.payment_method_brand?.toUpperCase() || "Carta"} ••••{item.payment_method_last4 || ""}
                    </div>
                  ) : (
                    <div style={{ fontSize: 10, color: "#9ca3af", marginTop: 4 }}>Carta non salvata</div>
                  )}
                  {item.cancellation_requested && (
                    <div style={{ fontSize: 9, color: "#d97706", fontWeight: 700, marginTop: 4 }}>
                      ⚑ Disdetta richiesta
                    </div>
                  )}
                </td>

                {/* Release / Bundle */}
                <td style={td}>
                  <div style={{ fontSize: 11, marginBottom: 2 }}>
                    <span style={{ color: "#6b7280" }}>Assegnata: </span>
                    <strong>{item.assigned_release_version || item.delivery_assigned_release_version || "—"}</strong>
                  </div>
                  {item.installed_release_version && (
                    <div style={{ fontSize: 11 }}>
                      <span style={{ color: "#6b7280" }}>Installata: </span>
                      <strong>{item.installed_release_version}</strong>
                    </div>
                  )}
                  <div style={{ fontSize: 10, color: "#9ca3af", marginTop: 2 }}>
                    Target: {LATEST_RELEASE}
                  </div>
                  {item.bundle_generated_at && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 4 }}>
                      Generato: {fmtDt(item.bundle_generated_at)}
                    </div>
                  )}
                  {item.bundle_sent_at && (
                    <div style={{ fontSize: 10, color: "#16a34a" }}>
                      ✓ Inviato: {fmtDt(item.bundle_sent_at)}
                    </div>
                  )}
                  {item.delivery_status && (
                    <div style={{ marginTop: 4 }}>
                      {deliveryStatusBadge(item.delivery_status)}
                    </div>
                  )}
                </td>

                {/* Azioni */}
                <td style={td}>
                  <div style={{ display: "flex", flexDirection: "column", gap: 8, minWidth: 230 }}>

                    {/* Slot: confirm — only when slot_requested */}
                    {item.onboarding_status === "slot_requested" && (
                      <div style={actionGroup}>
                        <div style={actionGroupLabel}>📅 Slot</div>
                        <input
                          type="datetime-local"
                          value={slotScheduledByCustomer[item.customer_id] || ""}
                          onChange={(e) =>
                            setSlotScheduledByCustomer((prev) => ({ ...prev, [item.customer_id]: e.target.value }))
                          }
                          style={{ fontSize: 11 }}
                        />
                        <button
                          onClick={() => handleConfirmSlot(item.customer_id)}
                          disabled={busy(item.customer_id) || !slotScheduledByCustomer[item.customer_id]}
                          style={btnPrimary}
                        >
                          Conferma slot
                        </button>
                      </div>
                    )}

                    {/* Onboarding status — guided next step only */}
                    <div style={actionGroup}>
                      <div style={actionGroupLabel}>🔄 Onboarding</div>
                      {(() => {
                        const nextStatus = NEXT_ONBOARDING_STATUS[item.onboarding_status];
                        const waitingCustomerStatuses = ["draft", "signup_started", "checkout_started"];

                        if (waitingCustomerStatuses.includes(item.onboarding_status || "")) {
                          return (
                            <span style={{ fontSize: 11, color: "#9ca3af" }}>
                              In attesa azione cliente
                            </span>
                          );
                        }

                        if (!nextStatus) {
                          if (item.onboarding_status === "data_validated") {
                            return <span style={{ fontSize: 11, color: "#16a34a" }}>✓ Completato</span>;
                          }
                          return <span style={{ fontSize: 11, color: "#9ca3af" }}>Stato: {item.onboarding_status || "—"}</span>;
                        }

                        return (
                          <button
                            onClick={() => handleUpdateStatus(item.customer_id, nextStatus)}
                            disabled={busy(item.customer_id)}
                            style={btn}
                          >
                            → {nextStatus}
                          </button>
                        );
                      })()}
                    </div>

                    {/* Subscription */}
                    <div style={actionGroup}>
                      <div style={actionGroupLabel}>💳 Abbonamento</div>
                      {item.subscription_status === "active" ? (
                        <span style={{ fontSize: 11, color: "#16a34a" }}>✓ Attivo</span>
                      ) : (() => {
                        const canActivate =
                          item.onboarding_status === "data_validated" &&
                          item.payment_method_saved === true;
                        return (
                          <>
                            <button
                              onClick={() => handleActivateSub(item.customer_id)}
                              disabled={busy(item.customer_id) || !canActivate}
                              style={canActivate ? btnPrimary : btn}
                            >
                              Attiva abbonamento
                            </button>
                            {!canActivate && (
                              <span style={{ fontSize: 10, color: "#9ca3af" }}>
                                Richiede validazione dati e metodo di pagamento
                              </span>
                            )}
                          </>
                        );
                      })()}
                    </div>

                    {/* Delivery */}
                    {(() => {
                      const isAligned = item.assigned_release_version === LATEST_RELEASE;
                      return (
                        <div style={actionGroup}>
                          <div style={actionGroupLabel}>📦 Delivery</div>
                          {isAligned ? (
                            <span style={{ fontSize: 11, color: "#16a34a", fontWeight: 600 }}>✓ Sistema aggiornato</span>
                          ) : (
                            <button
                              onClick={() => handleSendRelease(item.customer_id)}
                              disabled={busy(item.customer_id)}
                              style={btnPrimary}
                            >
                              Invia release {LATEST_RELEASE}
                            </button>
                          )}
                          <div style={{ display: "flex", gap: 4, flexWrap: "wrap", marginTop: 2 }}>
                            <button onClick={() => handleAssignRelease(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                              Assign
                            </button>
                            <button onClick={() => handlePrepareDelivery(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                              Prepare
                            </button>
                            <button onClick={() => handleMarkSent(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                              Mark sent
                            </button>
                          </div>
                        </div>
                      );
                    })()}

                  </div>
                </td>
              </tr>
            ))}

            {!loading && filteredItems.length === 0 && (
              <tr>
                <td colSpan={6} style={{ ...td, textAlign: "center", padding: 40, color: "#9ca3af" }}>
                  {search || quickFilter !== "tutti" ? "Nessun cliente corrisponde al filtro." : "Nessun cliente trovato."}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

const page: React.CSSProperties = {
  padding: "20px 28px 32px",
  maxWidth: 1280,
  margin: "0 auto",
  textAlign: "left",
};

const headerBox: React.CSSProperties = {
  display: "flex",
  alignItems: "flex-start",
  justifyContent: "space-between",
  gap: 16,
  marginBottom: 18,
  paddingBottom: 18,
  borderBottom: "1px solid #e5e7eb",
};

const summaryGrid: React.CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(135px, 1fr))",
  gap: 10,
  marginBottom: 16,
};

const toolbarBox: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: 12,
  flexWrap: "wrap",
  background: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: 12,
  padding: "12px 14px",
  marginBottom: 16,
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const tableCard: React.CSSProperties = {
  overflowX: "auto",
  background: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: 12,
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const statBox: React.CSSProperties = {
  background: "#ffffff",
  border: "1px solid #e5e7eb",
  borderRadius: 12,
  padding: "12px 16px",
  textAlign: "center",
  minWidth: 105,
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const searchInput: React.CSSProperties = {
  width: "100%",
  maxWidth: 460,
  padding: "8px 12px",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  fontSize: 14,
};

const th: React.CSSProperties = {
  borderBottom: "1px solid #e5e7eb",
  padding: "12px 14px",
  textAlign: "left",
  fontSize: 12,
  fontWeight: 800,
  color: "#374151",
  background: "#f8fafc",
};

const td: React.CSSProperties = {
  borderBottom: "1px solid #f3f4f6",
  padding: "12px 14px",
  verticalAlign: "top",
};

const actionGroup: React.CSSProperties = {
  background: "#f9fafb",
  border: "1px solid #f3f4f6",
  borderRadius: 6,
  padding: "6px 8px",
  display: "flex",
  flexDirection: "column",
  gap: 5,
};

const actionGroupLabel: React.CSSProperties = {
  fontSize: 10,
  fontWeight: 700,
  color: "#6b7280",
  textTransform: "uppercase",
  letterSpacing: "0.04em",
};

const btn: React.CSSProperties = {
  fontSize: 11,
  padding: "3px 8px",
  borderRadius: 4,
  border: "1px solid #e5e7eb",
  background: "white",
  cursor: "pointer",
};

const btnPrimary: React.CSSProperties = {
  fontSize: 11,
  padding: "3px 10px",
  borderRadius: 4,
  border: "1px solid #16a34a",
  background: "#dcfce7",
  color: "#166534",
  cursor: "pointer",
  fontWeight: 600,
};
