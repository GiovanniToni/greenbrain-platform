import { useEffect, useState } from "react";
import {
  downloadCustomerPortalBundle,
  getCustomerPortalMe,
} from "@/lib/customerPortalApi";
import { createPortalCheckout } from "@/lib/customerBillingApi";

export default function CustomerPortalDashboard() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [downloading, setDownloading] = useState(false);

  useEffect(() => {
    getCustomerPortalMe()
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : "Errore"))
      .finally(() => setLoading(false));
  }, []);

  async function handleDownloadBundle() {
    try {
      setDownloading(true);
      setError(null);

      const { blob, filename } = await downloadCustomerPortalBundle();
      const url = window.URL.createObjectURL(blob);

      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();

      window.URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore download bundle");
    } finally {
      setDownloading(false);
    }
  }

  async function handleStartCheckout() {
    try {
      setError(null);
      const data = await createPortalCheckout();
      if (!data?.checkout_url) {
        throw new Error("checkout_url mancante");
      }
      window.location.href = data.checkout_url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore avvio checkout");
    }
  }

  if (loading) return <div style={{ padding: 24 }}>Caricamento...</div>;
  if (error && !data) return <div style={{ padding: 24, color: "red" }}>{error}</div>;

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

      <div style={{ margin: "24px 0", padding: 16, border: "1px solid #ddd", borderRadius: 8 }}>
        <h2>Abbonamento</h2>
        <p><strong>Stato subscription:</strong> {data.subscription_status || "non attiva"}</p>
        <button onClick={handleStartCheckout}>
          Attiva abbonamento
        </button>
      </div>

      <h2>Delivery</h2>
      <p><strong>Bundle generato:</strong> {data.delivery?.bundle_generated_at || "-"}</p>
      <p><strong>Bundle inviato:</strong> {data.delivery?.bundle_sent_at || "-"}</p>
      <p><strong>Percorso bundle:</strong> {data.delivery?.bundle_local_path || "-"}</p>
      <p><strong>Install status:</strong> {data.delivery?.install_status || "-"}</p>
      <p><strong>Go live:</strong> {data.delivery?.go_live_at || "-"}</p>

      <div style={{ marginTop: 24 }}>
        <button onClick={handleDownloadBundle} disabled={!bundleReady || downloading}>
          {downloading ? "Download in corso..." : "Scarica bundle"}
        </button>
        {!bundleReady && <p style={{ marginTop: 8 }}>Bundle non ancora disponibile. Completa prima il provisioning.</p>}
      </div>

      {error && <p style={{ color: "red", marginTop: 16 }}>{error}</p>}

      <h2 style={{ marginTop: 32 }}>Dati grezzi</h2>
      <pre>{JSON.stringify(data, null, 2)}</pre>
    </div>
  );
}
