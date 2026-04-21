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

  return (
    <div style={{ padding: 24, textAlign: "left" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
        <h1 style={{ margin: 0 }}>Gestione clienti</h1>
        <button onClick={load} disabled={loading} style={{ fontSize: 13 }}>
          {loading ? "Caricamento..." : "Ricarica"}
        </button>
      </div>

      {/* summary strip */}
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 16 }}>
        {([
          { label: "Totale", value: stats.total },
          { label: "Pagamento salvato", value: stats.paymentSaved },
          { label: "Slot richiesti", value: stats.slotRequested },
          { label: "Val. pendente", value: stats.dataValidationPending },
          { label: "Abbonamenti attivi", value: stats.active },
        ] as const).map(({ label, value }) => (
          <div key={label} style={statBox}>
            <div style={{ fontSize: 20, fontWeight: 700, lineHeight: 1 }}>{value}</div>
            <div style={{ fontSize: 11, color: "#6b7280", marginTop: 3 }}>{label}</div>
          </div>
        ))}
      </div>

      {/* search + quick filters */}
      <div style={{ marginBottom: 8 }}>
        <input
          type="search"
          placeholder="Cerca per azienda, tenant, email..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={searchInput}
        />
      </div>
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
              padding: "4px 12px",
              borderRadius: 6,
              border: "1px solid",
              borderColor: quickFilter === f.key ? "#16a34a" : "#e5e7eb",
              background: quickFilter === f.key ? "#dcfce7" : "white",
              color: quickFilter === f.key ? "#166534" : "#374151",
              fontSize: 13,
              cursor: "pointer",
            }}
          >
            {f.label}
          </button>
        ))}
      </div>

      {error && (
        <div style={{ marginBottom: 16, color: "crimson" }}>
          <strong>Errore:</strong> {error}
        </div>
      )}

      {actionMessage && (
        <div style={{ marginBottom: 16 }}>
          <strong>Esito:</strong> {actionMessage}
        </div>
      )}

      <div style={{ overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr>
              <th style={th}>Company</th>
              <th style={th}>Tenant</th>
              <th style={th}>Email</th>
              <th style={th}>Onboarding</th>
              <th style={th}>Subscription</th>
              <th style={th}>Payment</th>
              <th style={th}>Slot</th>
              <th style={th}>Install</th>
              <th style={th}>DB</th>
              <th style={th}>Release</th>
              <th style={th}>Bundle generated</th>
              <th style={th}>Bundle sent</th>
              <th style={th}>Bundle path</th>
              <th style={th}>Azioni</th>
            </tr>
          </thead>
          <tbody>
            {filteredItems.map((item) => (
              <tr key={item.customer_id}>
                <td style={td}>{item.company_name}</td>
                <td style={td}>{item.tenant_code || "-"}</td>
                <td style={td}>{item.contact_email}</td>
                <td style={td}>
                  <div>{item.onboarding_status}</div>
                  {item.data_validated_at && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 2 }}>
                      Val.: {new Date(item.data_validated_at).toLocaleDateString("it-IT")}
                    </div>
                  )}
                </td>

                {/* subscription */}
                <td style={td}>
                  <div>{item.subscription_status || "—"}</div>
                  {item.subscription_plan && (
                    <div style={{ fontSize: 11, color: "#888" }}>{item.subscription_plan}</div>
                  )}
                </td>

                {/* payment */}
                <td style={td}>
                  {item.payment_method_saved ? (
                    <div>
                      <span style={{ color: "#16a34a" }}>✓</span>
                      {item.payment_method_last4 && (
                        <div style={{ fontSize: 11, color: "#888" }}>
                          {item.payment_method_brand?.toUpperCase() || ""} ••••&nbsp;{item.payment_method_last4}
                        </div>
                      )}
                    </div>
                  ) : "—"}
                </td>

                {/* slot */}
                <td style={td}>
                  {item.setup_slot_scheduled_for ? (
                    <div>
                      <div style={{ fontSize: 11 }}>
                        {new Date(item.setup_slot_scheduled_for).toLocaleString("it-IT")}
                      </div>
                      <div style={{ fontSize: 11, color: "#888" }}>confermato</div>
                    </div>
                  ) : item.setup_slot_preferred_date ? (
                    <div>
                      <div style={{ fontSize: 11 }}>{item.setup_slot_preferred_date}</div>
                      <div style={{ fontSize: 11, color: "#888" }}>
                        {item.setup_slot_preferred_time === "morning"
                          ? "Mattina"
                          : item.setup_slot_preferred_time === "afternoon"
                          ? "Pomeriggio"
                          : item.setup_slot_preferred_time || ""}
                      </div>
                    </div>
                  ) : "—"}
                  {item.setup_slot_confirmed_at && (
                    <div style={{ fontSize: 10, color: "#6b7280", marginTop: 2 }}>
                      conf.: {new Date(item.setup_slot_confirmed_at).toLocaleDateString("it-IT")}
                    </div>
                  )}
                </td>

                <td style={td}>{item.install_status}</td>
                <td style={td}>{item.db_integration_status}</td>
                <td style={td}>
                  <input
                    type="text"
                    value={releaseByCustomer[item.customer_id] || ""}
                    onChange={(e) =>
                      setReleaseByCustomer((prev) => ({
                        ...prev,
                        [item.customer_id]: e.target.value,
                      }))
                    }
                    style={{ width: 120 }}
                  />
                </td>
                <td style={td}>{item.bundle_generated_at || "-"}</td>
                <td style={td}>{item.bundle_sent_at || "-"}</td>
                <td style={td}>
                  <div style={{ maxWidth: 320, wordBreak: "break-all" }}>
                    {item.bundle_local_path || "-"}
                  </div>
                </td>

                {/* azioni */}
                <td style={td}>
                  <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>

                    {/* existing delivery controls */}
                    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                      <button
                        onClick={() => handleAssignRelease(item.customer_id)}
                        disabled={busyCustomerId === item.customer_id}
                      >
                        Assign release
                      </button>
                      <button
                        onClick={() => handlePrepareDelivery(item.customer_id)}
                        disabled={busyCustomerId === item.customer_id}
                      >
                        Prepare delivery
                      </button>
                      <button
                        onClick={() => handleMarkSent(item.customer_id)}
                        disabled={busyCustomerId === item.customer_id}
                      >
                        Mark sent
                      </button>
                    </div>

                    <hr style={{ borderColor: "#eee", margin: 0 }} />

                    {/* confirm slot — only when slot_requested */}
                    {item.onboarding_status === "slot_requested" && (
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
                        <input
                          type="datetime-local"
                          value={slotScheduledByCustomer[item.customer_id] || ""}
                          onChange={(e) =>
                            setSlotScheduledByCustomer((prev) => ({
                              ...prev,
                              [item.customer_id]: e.target.value,
                            }))
                          }
                          style={{ fontSize: 12 }}
                        />
                        <button
                          onClick={() => handleConfirmSlot(item.customer_id)}
                          disabled={
                            busyCustomerId === item.customer_id ||
                            !slotScheduledByCustomer[item.customer_id]
                          }
                        >
                          Conferma slot
                        </button>
                      </div>
                    )}

                    {/* onboarding status update */}
                    <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
                      <select
                        value={statusByCustomer[item.customer_id] || ""}
                        onChange={(e) =>
                          setStatusByCustomer((prev) => ({
                            ...prev,
                            [item.customer_id]: e.target.value,
                          }))
                        }
                        style={{ fontSize: 12 }}
                      >
                        <option value="">— stato —</option>
                        <option value="slot_confirmed">slot_confirmed</option>
                        <option value="setup_in_progress">setup_in_progress</option>
                        <option value="data_validation_pending">data_validation_pending</option>
                        <option value="data_validated">data_validated</option>
                      </select>
                      <button
                        onClick={() => handleUpdateStatus(item.customer_id)}
                        disabled={
                          busyCustomerId === item.customer_id ||
                          !statusByCustomer[item.customer_id]
                        }
                      >
                        Aggiorna
                      </button>
                    </div>

                    {/* activate subscription */}
                    {item.payment_method_saved && item.subscription_status !== "active" && (
                      <button
                        onClick={() => handleActivateSub(item.customer_id)}
                        disabled={busyCustomerId === item.customer_id}
                      >
                        Attiva abbonamento
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}

            {!loading && filteredItems.length === 0 && (
              <tr>
                <td style={td} colSpan={14}>
                  Nessun cliente trovato.
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
  minWidth: 110,
};

const searchInput: React.CSSProperties = {
  width: "100%",
  maxWidth: 400,
  padding: "7px 12px",
  border: "1px solid #e5e7eb",
  borderRadius: 8,
  fontSize: 14,
};

const th: React.CSSProperties = {
  borderBottom: "1px solid #ddd",
  padding: 10,
  textAlign: "left",
};

const td: React.CSSProperties = {
  borderBottom: "1px solid #eee",
  padding: 10,
  verticalAlign: "top",
};
