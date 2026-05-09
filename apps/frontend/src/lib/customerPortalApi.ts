import { getStoredToken, setRuntimeBaseUrl } from "@/lib/apiClient";
import { apiGet, apiPost } from "@/lib/apiClient";

const CENTRAL_API_BASE = (import.meta.env.VITE_API_BASE_URL ?? "https://www.greenbrain.it").replace(/\/$/, "");

export async function getCustomerPortalMe() {
  const profile = await apiGet("/api/v1/customer-portal/me");
  setRuntimeBaseUrl(profile?.runtime_public_backend_url);
  return profile;
}

export async function bookSetupSlot(payload: {
  preferred_date: string;
  preferred_time: string;
  notes?: string;
}) {
  return apiPost("/api/v1/customer-portal/book-setup-slot", payload);
}

export async function confirmDataOk() {
  return apiPost("/api/v1/customer-portal/confirm-data-ok", {});
}

export async function cancelPortalSubscription() {
  return apiPost("/api/v1/customer-portal/cancel-subscription", {});
}

export async function downloadCustomerPortalBundle(): Promise<{ blob: Blob; filename: string }> {
  const token = getStoredToken();

  if (!token) {
    throw new Error("Token non trovato. Effettua di nuovo il login.");
  }

  const response = await fetch(`${CENTRAL_API_BASE}/api/v1/customer-portal/download-bundle?t=${Date.now()}`, {
    method: "GET",
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${token}`,
      "Cache-Control": "no-cache",
      Pragma: "no-cache",
    },
  });

  if (!response.ok) {
    let detail = "Download bundle fallito";
    try {
      const data = await response.json();
      detail = data?.detail || detail;
    } catch {
      // ignore
    }
    throw new Error(detail);
  }

  const disposition = response.headers.get("content-disposition") || "";
  const match = disposition.match(/filename="?([^"]+)"?/i);
  const filename = match?.[1] || "greenbrain-bundle.tar.gz";

  const blob = await response.blob();
  return { blob, filename };
}
