import { useEffect, useMemo, useState } from "react";
import {
  assignRelease,
  listCustomers,
  markDeliverySent,
  prepareDelivery,
  type CustomerOpsItem,
} from "@/lib/customerOpsApi";

export default function Customers() {
  const [items, setItems] = useState<CustomerOpsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [releaseByCustomer, setReleaseByCustomer] = useState<Record<string, string>>({});
  const [busyCustomerId, setBusyCustomerId] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);

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

  return (
    <div style={{ padding: 24, textAlign: "left" }}>
      <h1>Customers</h1>
      <p>Vista clienti con assegnazione release, delivery plan e stato bundle.</p>

      <div style={{ marginBottom: 16 }}>
        <button onClick={load} disabled={loading}>
          {loading ? "Caricamento..." : "Ricarica"}
        </button>
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
            {sortedItems.map((item) => (
              <tr key={item.customer_id}>
                <td style={td}>{item.company_name}</td>
                <td style={td}>{item.tenant_code || "-"}</td>
                <td style={td}>{item.contact_email}</td>
                <td style={td}>{item.onboarding_status}</td>
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
                <td style={td}>
                  <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
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
                </td>
              </tr>
            ))}

            {!loading && sortedItems.length === 0 && (
              <tr>
                <td style={td} colSpan={11}>
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
