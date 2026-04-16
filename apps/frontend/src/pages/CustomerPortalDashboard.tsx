import { useEffect, useState } from "react";
import {
  getCustomerPortalBundleDownloadUrl,
  getCustomerPortalMe,
} from "@/lib/customerPortalApi";

export default function CustomerPortalDashboard() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getCustomerPortalMe()
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Errore"))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div style={{ padding: 24 }}>Caricamento...</div>;
  if (error) return <div style={{ padding: 24, color: "red" }}>{error}</div>;

  const bundleReady = Boolean(data?.delivery?.bundle_local_path);

  return (
    <div style={{ maxWidth: 900, margin: "40px auto", fontFamily: "sans-serif" }}>
      <h1>Area Cliente GreenBrain</h1>

      <p><strong>Azienda:</strong> {data.company_name}</p>
      <p><strong>Tenant:</strong> {data.tenant_code}</p>
      <p><strong>Email portale:</strong> {data.portal_user_email}</p>
      <p><strong>Onboarding:</strong> {data.onboarding_status}</p>
      <p><strong>Step:</strong> {data.onboarding_step || "-"}</p>
      <p><strong>Release assegnata:</strong> {data.assigned_release_version || "-"}</p>
      <p><strong>Versione installata:</strong> {data.installed_release_version || "-"}</p>

      <h2>Delivery</h2>
      <p><strong>Bundle generato:</strong> {data.delivery?.bundle_generated_at || "-"}</p>
      <p><strong>Bundle inviato:</strong> {data.delivery?.bundle_sent_at || "-"}</p>
      <p><strong>Percorso bundle:</strong> {data.delivery?.bundle_local_path || "-"}</p>
      <p><strong>Install status:</strong> {data.delivery?.install_status || "-"}</p>
      <p><strong>Go live:</strong> {data.delivery?.go_live_at || "-"}</p>

      <div style={{ marginTop: 24 }}>
        {bundleReady ? (
          <a
            href={getCustomerPortalBundleDownloadUrl()}
            style={{
              display: "inline-block",
              padding: "10px 14px",
              border: "1px solid #ccc",
              textDecoration: "none",
              borderRadius: 8,
            }}
          >
            Scarica bundle cliente
          </a>
        ) : (
          <p>Bundle non ancora pronto.</p>
        )}
      </div>

      <h2 style={{ marginTop: 32 }}>Dati grezzi</h2>
      <pre>{JSON.stringify(data, null, 2)}</pre>
    </div>
  );
}
