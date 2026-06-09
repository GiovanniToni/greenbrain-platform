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

  const disposition =
    response.headers.get("content-disposition") ||
    response.headers.get("Content-Disposition") ||
    "";

  const filenameStarMatch = disposition.match(/filename\*=UTF-8''([^;]+)/i);
  const filenameMatch = disposition.match(/filename="?([^";]+)"?/i);

  const filename = filenameStarMatch?.[1]
    ? decodeURIComponent(filenameStarMatch[1])
    : filenameMatch?.[1] || "GreenBrain-Installer.zip";

  const blob = await response.blob();
  return { blob, filename };
}

export type SourceDbIntegration = {
  customer_id?: string | null;
  db_type?: string | null;
  db_host?: string | null;
  db_port?: number | null;
  db_name?: string | null;
  db_schema?: string | null;
  source_client_code?: string | null;
  db_view_name?: string | null;
  db_username?: string | null;
  db_password_set?: boolean;
  db_encrypt?: boolean | null;
  db_trust_server_certificate?: boolean | null;
  manager_contact_email?: string | null;
  manager_response_raw_text?: string | null;
  manager_response_received_at?: string | null;
  formal_validation_status?: string | null;
  formal_validation_report?: string | null;
  formal_validation_result?: {
    missing?: string[];
    warnings?: string[];
    [key: string]: unknown;
  };
  formal_validation_at?: string | null;
  technical_test_status?: string | null;
  technical_test_report?: string | null;
  technical_test_result?: Record<string, unknown>;
  technical_test_at?: string | null;
  last_error_report?: string | null;
  last_error_at?: string | null;
  notes?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

export type SourceDbPortalState = {
  customer_id?: string | null;
  tenant_code?: string | null;
  db_integration_status?: string | null;
  source_db_integration?: SourceDbIntegration | null;
};

export type SourceDbIntegrationPayload = {
  db_type?: string;
  db_host?: string;
  db_port?: number;
  db_name?: string;
  db_schema?: string;
  source_client_code?: string;
  db_view_name?: string;
  db_username?: string;
  password?: string;
  db_encrypt?: boolean;
  db_trust_server_certificate?: boolean;
  manager_contact_email?: string;
  manager_response_raw_text?: string;
  notes?: string;
};

export async function getCustomerSourceDbState(): Promise<SourceDbPortalState> {
  return apiGet("/api/v1/customer-portal/source-db");
}

export async function saveCustomerSourceDbState(
  payload: SourceDbIntegrationPayload,
): Promise<SourceDbPortalState> {
  return apiPost("/api/v1/customer-portal/source-db", payload);
}

