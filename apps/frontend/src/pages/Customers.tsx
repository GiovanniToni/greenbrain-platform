import { useEffect, useState } from "react";
import { apiGet } from "@/lib/apiClient";

type CustomerItem = {
  customer_id: string;
  tenant_code?: string | null;
  company_name: string;
  contact_email: string;
  onboarding_status: string;
  install_status: string;
  db_integration_status: string;
  assigned_release_version?: string | null;
  installed_release_version?: string | null;
};

export default function Customers() {
  const [items, setItems] = useState<CustomerItem[]>([]);
  const [error, setError] = useState<string>("");

  useEffect(() => {
    apiGet("/api/v1/customer-ops/customers?limit=100")
      .then((res) => {
        setItems(res.items || []);
        setError("");
      })
      .catch((err) => {
        console.error(err);
        setError("Errore caricamento customer ops");
      });
  }, []);

  return (
    <div style={{ padding: 24 }}>
      <h1>Customer Ops</h1>
      <p>Lista clienti registrati nel control plane Supabase.</p>

      {error ? <p>{error}</p> : null}

      <table border={1} cellPadding={8} cellSpacing={0}>
        <thead>
          <tr>
            <th>Tenant</th>
            <th>Azienda</th>
            <th>Email</th>
            <th>Onboarding</th>
            <th>Install</th>
            <th>DB Integration</th>
            <th>Assigned</th>
            <th>Installed</th>
          </tr>
        </thead>
        <tbody>
          {items.map((c) => (
            <tr key={c.customer_id}>
              <td>{c.tenant_code || "-"}</td>
              <td>{c.company_name}</td>
              <td>{c.contact_email}</td>
              <td>{c.onboarding_status}</td>
              <td>{c.install_status}</td>
              <td>{c.db_integration_status}</td>
              <td>{c.assigned_release_version || "-"}</td>
              <td>{c.installed_release_version || "-"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
