import { apiPost } from "@/lib/apiClient";

export async function createPortalCheckout() {
  return apiPost("/api/v1/customer-billing/portal-checkout", {});
}
