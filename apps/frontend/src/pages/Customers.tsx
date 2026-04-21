import { useEffect, useMemo, useState } from "react";
import {
  assignRelease,
  confirmCustomerSlot,
  activateCustomerSubscription,
  listCustomers,
  markDeliverySent,
  prepareDelivery,
  updateCustomerOnboardingStatus,
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

function fmtDt(iso: string | null | undefined, mode: "date" | "datetime" = "date") {
  if (!iso) return null;
  try {
    return mode === "datetime"
      ? new Date(iso).toLocaleString("it-IT")
      : new Date(iso).toLocaleDateString("it-IT");
  } catch { return iso; }
}

export default function Customers() {
  const [items, setItems] = useState<CustomerOpsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [releaseByCustomer, setReleaseByCustomer] = useState<Record<string, string>>({});
  const [busyCustomerId, setBusyCustomerId] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [slotScheduledByCustomer, setSlotScheduledByCustomer] = useState<Record<string, string>>({});
  const [statusByCustomer, setStatusByCustomer] = useState<Record<string, string>>({});
  const [search, setSearch] = useState("");
  const [quickFilter, setQuickFilter] = useState("tutti");

  const defaultRelease = "0.1.12";

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
    slotRequested: items.filter((x) =>
      x.onboarding_status === "slot_requested" || x.onboarding_status === "slot_confirmed"
    ).length,
    dataValidationPending: items.filter((x) => x.onboarding_status === "data_validation_pending").length,
    active: items.filter((x) => x.subscription_status === "active").length,
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

  async function handleUpdateStatus(customerId: string) {
    const newStatus = statusByCustomer[customerId];
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
    <div style={{ padding: 24, textAlign: "left" }}>

      {/* header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
        <h1 style={{ margin: 0 }}>Gestione clienti</h1>
        <button onClick={load} disabled={loading} style={{ fontSize: 13 }}>
          {loading ? "Caricamento..." : "↺ Ricarica"}
        </button>
      </div>

      {/* summary strip */}
      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 16 }}>
        {([
          { label: "Totale", value: stats.total },
          { label: "Pagamento salvato", value: stats.paymentSaved },
          { label: "Slot richiesti", value: stats.slotRequested },
          { label: "Val. pendente", value: stats.dataValidationPending },
          { label: "Abbonamenti attivi", value: stats.active },
        ] as const).map(({ label, value }) => (
          <div key={label} style={statBox}>
            <div style={{ fontSize: 22, fontWeight: 800, lineHeight: 1 }}>{value}</div>
            <div style={{ fontSize: 10, color: "#6b7280", marginTop: 3 }}>{label}</div>
          </div>
        ))}
      </div>

      {/* search */}
      <div style={{ marginBottom: 8 }}>
        <input
          type="search"
          placeholder="Cerca per azienda, tenant, email..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={searchInput}
        />
      </div>

      {/* quick filters */}
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 16 }}>
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
      <div style={{ overflowX: "auto" }}>
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
                  <div style={{ fontWeight: 600, fontSize: 14 }}>{item.company_name}</div>
                  <div style={{ fontSize: 11, color: "#6b7280", marginTop: 2 }}>{item.tenant_code || "—"}</div>
                  <div style={{ fontSize: 11, color: "#9ca3af" }}>{item.contact_email}</div>
                </td>

                {/* Onboarding */}
                <td style={td}>
                  {statusBadge(item.onboarding_status)}
                  {item.data_validated_at && (
                    <div style={{ fontSize: 10, color: "#16a34a", marginTop: 4 }}>
                      ✓ Validato: {fmtDt(item.data_validated_at)}
                    </div>
                  )}
                  <div style={{ fontSize: 10, color: "#9ca3af", marginTop: 4 }}>
                    Install: {item.install_status}
                  </div>
                  <div style={{ fontSize: 10, color: "#9ca3af" }}>
                    DB: {item.db_integration_status}
                  </div>
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
                </td>

                {/* Release / Bundle */}
                <td style={td}>
                  <input
                    type="text"
                    value={releaseByCustomer[item.customer_id] || ""}
                    onChange={(e) =>
                      setReleaseByCustomer((prev) => ({ ...prev, [item.customer_id]: e.target.value }))
                    }
                    style={{ width: 100, fontSize: 12 }}
                  />
                  {item.bundle_generated_at && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 4 }}>
                      Gen.: {fmtDt(item.bundle_generated_at)}
                    </div>
                  )}
                  {item.bundle_sent_at && (
                    <div style={{ fontSize: 10, color: "#6b7280" }}>
                      Inv.: {fmtDt(item.bundle_sent_at)}
                    </div>
                  )}
                  {item.bundle_local_path && (
                    <div style={{ fontSize: 9, color: "#9ca3af", wordBreak: "break-all", maxWidth: 200, marginTop: 2 }}>
                      {item.bundle_local_path}
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

                    {/* Onboarding status */}
                    <div style={actionGroup}>
                      <div style={actionGroupLabel}>🔄 Onboarding</div>
                      <div style={{ display: "flex", gap: 4 }}>
                        <select
                          value={statusByCustomer[item.customer_id] || ""}
                          onChange={(e) =>
                            setStatusByCustomer((prev) => ({ ...prev, [item.customer_id]: e.target.value }))
                          }
                          style={{ fontSize: 11, flex: 1 }}
                        >
                          <option value="">— stato —</option>
                          <option value="slot_confirmed">slot_confirmed</option>
                          <option value="setup_in_progress">setup_in_progress</option>
                          <option value="data_validation_pending">data_validation_pending</option>
                          <option value="data_validated">data_validated</option>
                        </select>
                        <button
                          onClick={() => handleUpdateStatus(item.customer_id)}
                          disabled={busy(item.customer_id) || !statusByCustomer[item.customer_id]}
                          style={btn}
                        >
                          Salva
                        </button>
                      </div>
                    </div>

                    {/* Subscription */}
                    <div style={actionGroup}>
                      <div style={actionGroupLabel}>💳 Abbonamento</div>
                      {item.subscription_status === "active" ? (
                        <span style={{ fontSize: 11, color: "#16a34a" }}>✓ Attivo</span>
                      ) : item.payment_method_saved ? (
                        <button
                          onClick={() => handleActivateSub(item.customer_id)}
                          disabled={busy(item.customer_id)}
                          style={btnPrimary}
                        >
                          Attiva abbonamento
                        </button>
                      ) : (
                        <span style={{ fontSize: 11, color: "#9ca3af" }}>In attesa carta</span>
                      )}
                    </div>

                    {/* Delivery */}
                    <div style={actionGroup}>
                      <div style={actionGroupLabel}>📦 Delivery</div>
                      <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
                        <button onClick={() => handleAssignRelease(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                          Assign release
                        </button>
                        <button onClick={() => handlePrepareDelivery(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                          Prepare
                        </button>
                        <button onClick={() => handleMarkSent(item.customer_id)} disabled={busy(item.customer_id)} style={btn}>
                          Mark sent
                        </button>
                      </div>
                    </div>

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

const statBox: React.CSSProperties = {
  background: "#f9fafb",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  padding: "10px 16px",
  textAlign: "center",
  minWidth: 105,
};

const searchInput: React.CSSProperties = {
  width: "100%",
  maxWidth: 420,
  padding: "7px 12px",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  fontSize: 14,
};

const th: React.CSSProperties = {
  borderBottom: "2px solid #e5e7eb",
  padding: "10px 12px",
  textAlign: "left",
  fontSize: 12,
  fontWeight: 700,
  color: "#374151",
  background: "#f9fafb",
};

const td: React.CSSProperties = {
  borderBottom: "1px solid #f3f4f6",
  padding: "10px 12px",
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
