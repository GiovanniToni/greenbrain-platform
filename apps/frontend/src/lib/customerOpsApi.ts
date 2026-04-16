import { apiGet, apiPost } from "@/lib/apiClient";

export type CustomerOpsItem = {
  customer_id: string;
  tenant_code?: string | null;
  company_name: string;
  contact_name?: string | null;
  contact_email: string;
  contact_phone?: string | null;
  onboarding_status: string;
  install_status: string;
  db_integration_status: string;
  assigned_release_version?: string | null;
  installed_release_version?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

export type AssignReleaseResponse = {
  status: string;
  customer_id: string;
  assigned_release_version: string;
  customer?: Record<string, unknown>;
  delivery?: Record<string, unknown>;
};

export type PrepareDeliveryResponse = {
  status: string;
  customer_id: string;
  tenant_code?: string;
  company_name?: string;
  assigned_release_version?: string;
  message?: string;
};

export async function listCustomers(limit = 100): Promise<{ items: CustomerOpsItem[] }> {
  return apiGet(`/api/v1/customer-ops/customers?limit=${limit}`);
}

export async function assignRelease(
  customer_id: string,
  assigned_release_version: string,
): Promise<AssignReleaseResponse> {
  return apiPost("/api/v1/customer-provisioning/assign-release", {
    customer_id,
    assigned_release_version,
  });
}

export async function prepareDelivery(
  customer_id: string,
): Promise<PrepareDeliveryResponse> {
  return apiPost("/api/v1/customer-delivery/prepare", {
    customer_id,
  });
}
