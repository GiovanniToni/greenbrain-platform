import { apiGet, apiPatch, apiPost } from "@/lib/apiClient";

export type CustomerSourceDbIntegration = {
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

export type CustomerSecurityAlert = {
  id: string;
  customer_id?: string | null;
  tenant_code?: string | null;
  email: string;
  alert_type: string;
  status: string;
  severity: "info" | "warning" | "error" | string;
  title: string;
  message: string;
  source?: string | null;
  first_seen_at?: string | null;
  last_seen_at?: string | null;
  resolved_at?: string | null;
  details?: Record<string, unknown>;
};

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
  runtime_connection_status?: string | null;
  latest_installation_id?: string | null;
  last_runtime_heartbeat_at?: string | null;
  runtime_public_backend_url?: string | null;
  runtime_local_backend_url?: string | null;
  runtime_local_agent_version?: string | null;
  runtime_connection_mode?: string | null;
  runtime_last_sync_status?: string | null;
  runtime_last_sync_at?: string | null;
  platform_ready?: boolean;
  installation_status?: string | null;
  installation_status_label?: string | null;
  installation_next_action?: string | null;
  last_downloaded_release_version?: string | null;
  last_downloaded_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;

  subscription_status?: string | null;
  subscription_plan?: string | null;
  payment_method_saved?: boolean;
  payment_method_last4?: string | null;
  payment_method_brand?: string | null;
  setup_slot_preferred_date?: string | null;
  setup_slot_preferred_time?: string | null;
  setup_slot_requested_at?: string | null;
  setup_slot_confirmed_at?: string | null;
  setup_slot_scheduled_for?: string | null;
  data_validated_at?: string | null;

  delivery_assigned_release_version?: string | null;
  bundle_generated_at?: string | null;
  bundle_sent_at?: string | null;
  bundle_local_path?: string | null;
  delivery_install_status?: string | null;
  delivery_onboarding_status?: string | null;
  go_live_at?: string | null;
  delivery_updated_at?: string | null;
  delivery_status?: string | null;
  cancellation_requested?: boolean;
  cancellation_requested_at?: string | null;
  subscription_cancel_at_period_end?: boolean | null;
  subscription_current_period_end?: string | null;
  active_security_alerts?: CustomerSecurityAlert[];
  active_password_reset_alert?: CustomerSecurityAlert | null;
  source_db_integration?: CustomerSourceDbIntegration | null;
};

export const DELIVERY_STATUS_LABELS: Record<string, string> = {
  pending:   "In attesa",
  prepared:  "Preparato",
  sent:      "Inviato",
  installed: "Installato",
  failed:    "Errore",
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

export type MarkSentResponse = {
  status: string;
  customer_id: string;
  bundle_sent_at?: string;
  delivery?: Record<string, unknown>;
};

export type SendReleaseResponse = {
  customer_id: string;
  assigned_release_version: string;
  bundle_generated_at?: string | null;
  bundle_local_path?: string | null;
  delivery_status: string;
};

export type PasswordResetLinkResponse = {
  status: string;
  customer_id: string;
  tenant_code?: string | null;
  company_name?: string | null;
  email: string;
  reset_url: string;
  token_hint?: string | null;
  expires_at?: string | null;
  expires_minutes: number;
  source: string;
  safety: {
    token_hash_exposed: boolean;
    password_changed: boolean;
    raw_token_stored: boolean;
  };
};

export async function createCustomerPasswordResetLink(
  customer_id: string,
): Promise<PasswordResetLinkResponse> {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/password-reset-link`, {});
}

export async function listCustomers(limit = 100): Promise<{ items: CustomerOpsItem[] }> {
  return apiGet(`/api/v1/customer-ops/customers?limit=${limit}`);
}

export async function getCustomerById(customer_id: string): Promise<CustomerOpsItem> {
  return apiGet(`/api/v1/customer-ops/customers/${customer_id}`);
}

export async function sendRelease(
  customer_id: string,
  release_version: string,
): Promise<SendReleaseResponse> {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/send-release`, {
    release_version,
  });
}

export async function requestCustomerCancellation(customer_id: string) {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/request-cancellation`, {});
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

export async function markDeliverySent(
  customer_id: string,
): Promise<MarkSentResponse> {
  return apiPost("/api/v1/customer-delivery/mark-sent", {
    customer_id,
  });
}

export async function confirmCustomerSlot(
  customer_id: string,
  scheduled_for: string,
) {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/confirm-slot`, {
    setup_slot_scheduled_for: scheduled_for,
  });
}

export async function updateCustomerOnboardingStatus(
  customer_id: string,
  onboarding_status: string,
) {
  return apiPatch(`/api/v1/customer-ops/customers/${customer_id}/onboarding-status`, {
    onboarding_status,
  });
}

export async function activateCustomerSubscription(customer_id: string) {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/activate-subscription`, {});
}

export async function forceActivateCustomerSubscription(customer_id: string) {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/force-activate-subscription`, {});
}


export type AdminUserCreatePayload = {
  email: string;
  password: string;
  full_name?: string;
};

export async function createAdminUser(payload: AdminUserCreatePayload) {
  return apiPost("/api/v1/auth/admin-users", payload);
}

export type CustomerOpsNotificationsResponse = {
  items: CustomerSecurityAlert[];
  active_count: number;
  unread_count: number;
};

export async function getCustomerOpsNotifications(limit = 20): Promise<CustomerOpsNotificationsResponse> {
  return apiGet(`/api/v1/customer-ops/notifications?limit=${limit}`);
}

export async function markCustomerPasswordResetAlertLinkSent(customer_id: string) {
  return apiPost(`/api/v1/customer-ops/customers/${customer_id}/password-reset-alert/mark-link-sent`, {});
}
