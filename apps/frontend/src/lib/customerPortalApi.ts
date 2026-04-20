import { getStoredToken } from "@/lib/apiClient";
import { apiGet, apiPost } from "@/lib/apiClient";

export async function getCustomerPortalMe() {
  return apiGet("/api/v1/customer-portal/me");
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

export async function downloadCustomerPortalBundle(): Promise<{ blob: Blob; filename: string }> {
  const token = getStoredToken();

  if (!token) {
    throw new Error("Token non trovato. Effettua di nuovo il login.");
  }

  const response = await fetch("/api/v1/customer-portal/download-bundle", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
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
